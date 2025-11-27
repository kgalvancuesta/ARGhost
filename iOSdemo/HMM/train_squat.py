import cv2
import numpy as np
import json
import math
import mediapipe as mp

VIDEO_PATH = "squats.MOV"
OUTPUT_JSON = "squat_hmm_model.json"

mp_pose = mp.solutions.pose
LMS = mp_pose.PoseLandmark

# We’ll focus on these joints (matching what you care about for squats)
JOINT_ORDER = [
    LMS.LEFT_SHOULDER,
    LMS.RIGHT_SHOULDER,
    LMS.LEFT_HIP,
    LMS.RIGHT_HIP,
    LMS.LEFT_KNEE,
    LMS.RIGHT_KNEE,
    LMS.LEFT_ANKLE,
    LMS.RIGHT_ANKLE,
]

NUM_FEATURES = 16   # (x,y) for 8 joints
NUM_STATES = 2      # 0 = up, 1 = down


# ---------- Geometry + feature extraction ----------

def angle(a, b, c):
    """Angle at point b given a-b-c, in degrees."""
    ax, ay = a
    bx, by = b
    cx, cy = c
    v1 = np.array([ax - bx, ay - by])
    v2 = np.array([cx - bx, cy - by])
    if np.linalg.norm(v1) < 1e-6 or np.linalg.norm(v2) < 1e-6:
        return 180.0
    v1 /= np.linalg.norm(v1)
    v2 /= np.linalg.norm(v2)
    dot = np.clip(np.dot(v1, v2), -1.0, 1.0)
    return float(np.degrees(np.arccos(dot)))


def extract_feature_vector(landmarks):
    """
    landmarks: result.pose_landmarks.landmark (mediapipe)
    Return 16-dim normalized feature vector or None if anything is missing.
    Normalization:
      - origin at hip center
      - scale = shoulder–hip distance
    """

    def get(lm):
        p = landmarks[lm]
        # visibility ~ confidence
        if p.visibility < 0.3:
            return None
        return (p.x, p.y)

    pts = {}
    for lm in JOINT_ORDER:
        p = get(lm)
        if p is None:
            return None
        pts[lm] = p

    lh = pts[LMS.LEFT_HIP]
    rh = pts[LMS.RIGHT_HIP]
    ls = pts[LMS.LEFT_SHOULDER]
    rs = pts[LMS.RIGHT_SHOULDER]

    hip_center = ((lh[0] + rh[0]) / 2.0, (lh[1] + rh[1]) / 2.0)
    shoulder_center = ((ls[0] + rs[0]) / 2.0, (ls[1] + rs[1]) / 2.0)

    def dist(a, b):
        return math.hypot(a[0] - b[0], a[1] - b[1])

    # scale = shoulder-hip distance (rough body scale)
    scale = dist(hip_center, shoulder_center)
    if scale < 1e-3:
        # fallback: hip distance
        scale = dist(lh, rh)
        if scale < 1e-3:
            return None

    def norm(p):
        return ((p[0] - hip_center[0]) / scale,
                (p[1] - hip_center[1]) / scale)

    ls_n = norm(ls)
    rs_n = norm(rs)
    lh_n = norm(lh)
    rh_n = norm(rh)
    lk_n = norm(pts[LMS.LEFT_KNEE])
    rk_n = norm(pts[LMS.RIGHT_KNEE])
    la_n = norm(pts[LMS.LEFT_ANKLE])
    ra_n = norm(pts[LMS.RIGHT_ANKLE])

    feat = [
        ls_n[0], ls_n[1],
        rs_n[0], rs_n[1],
        lh_n[0], lh_n[1],
        rh_n[0], rh_n[1],
        lk_n[0], lk_n[1],
        rk_n[0], rk_n[1],
        la_n[0], la_n[1],
        ra_n[0], ra_n[1],
    ]
    return feat


def knee_state(landmarks, up_threshold=150.0, down_threshold=120.0):
    """
    Simple heuristic: average knee angle → Up (0) or Down (1).
    Bigger angle (~180°) means straight leg (Up), smaller means bent (Down).
    """

    def get(lm):
        p = landmarks[lm]
        return (p.x, p.y)

    hip_l = get(LMS.LEFT_HIP)
    knee_l = get(LMS.LEFT_KNEE)
    ankle_l = get(LMS.LEFT_ANKLE)

    hip_r = get(LMS.RIGHT_HIP)
    knee_r = get(LMS.RIGHT_KNEE)
    ankle_r = get(LMS.RIGHT_ANKLE)

    ang_l = angle(hip_l, knee_l, ankle_l)
    ang_r = angle(hip_r, knee_r, ankle_r)
    ang = 0.5 * (ang_l + ang_r)

    if ang >= up_threshold:
        return 0  # Up
    elif ang <= down_threshold:
        return 1  # Down
    else:
        mid = 0.5 * (up_threshold + down_threshold)
        return 0 if ang >= mid else 1


# ---------- HMM helpers ----------

def fit_gaussians(features_per_state):
    """
    features_per_state[s] = list of feature vectors for state s
    Return per-state means and stds as [S x D]
    """
    means = []
    stds = []
    for s in range(NUM_STATES):
        arr = np.array(features_per_state[s])  # [N_s, D]
        mu = arr.mean(axis=0)
        sd = arr.std(axis=0)
        sd[sd < 1e-6] = 1e-6
        means.append(mu.tolist())
        stds.append(sd.tolist())
    return means, stds


def fit_transitions(state_seq):
    """
    state_seq: list of 0/1 states
    Return transition matrix [S x S] with Laplace smoothing.
    """
    counts = np.ones((NUM_STATES, NUM_STATES))  # Laplace smoothing
    for i in range(len(state_seq) - 1):
        a = state_seq[i]
        b = state_seq[i + 1]
        counts[a, b] += 1.0
    trans = counts / counts.sum(axis=1, keepdims=True)
    return trans


def fit_prior(first_state):
    """
    Simple prior: strongly favor the initial state (usually 'Up').
    """
    prior = np.full(NUM_STATES, 1e-6)
    prior[first_state] = 1.0
    prior /= prior.sum()
    return prior


def viterbi_loglik(sequence, log_prior, log_trans, means, stds):
    """
    sequence: [T x D]
    log_prior: [S]
    log_trans: [S x S]
    means/stds: [S x D]
    Return: (best_path, log_likelihood)
    """
    seq = np.array(sequence, dtype=np.float64)
    T, D = seq.shape
    S = len(log_prior)

    # log emission probabilities
    log_emit = np.zeros((T, S))
    for s in range(S):
        mu = np.array(means[s])
        sd = np.array(stds[s])
        var2 = 2.0 * sd * sd
        log_norm = -0.5 * np.log(2.0 * np.pi * sd * sd)
        diff = seq - mu
        # sum over dimensions
        log_emit[:, s] = log_norm.sum() - ((diff * diff) / var2).sum(axis=1)

    dp = np.full((T, S), -np.inf)
    back = np.full((T, S), -1, dtype=int)

    # init
    dp[0, :] = log_prior + log_emit[0, :]

    # recursion
    for t in range(1, T):
        for s in range(S):
            candidates = dp[t - 1, :] + log_trans[:, s]
            best_prev = int(np.argmax(candidates))
            dp[t, s] = candidates[best_prev] + log_emit[t, s]
            back[t, s] = best_prev

    # termination
    last_state = int(np.argmax(dp[T - 1, :]))
    best_log = float(dp[T - 1, last_state])

    path = [0] * T
    s = last_state
    for t in reversed(range(T)):
        path[t] = s
        s = back[t, s] if t > 0 else s

    return path, best_log


def segment_reps(frame_states):
    """
    Roughly find UP->DOWN->UP cycles as reps.
    Returns list of (start, end) frame indices.
    """
    reps = []
    i = 0
    n = len(frame_states)

    while i < n - 1:
        # find UP
        while i < n and frame_states[i] != 0:
            i += 1
        if i >= n - 1:
            break
        start = i

        # find DOWN after UP
        while i < n and frame_states[i] == 0:
            i += 1
        if i >= n:
            break

        # now in DOWN
        saw_down = False
        while i < n and frame_states[i] == 1:
            saw_down = True
            i += 1
        if not saw_down:
            break

        # first frame after DOWN (back to UP or neutral) marks end
        if i >= n:
            break
        end = i
        reps.append((start, end))

    return reps


# ---------- Main pipeline ----------

def main():
    cap = cv2.VideoCapture(VIDEO_PATH)
    if not cap.isOpened():
        print(f"Error: cannot open {VIDEO_PATH}")
        return

    all_features = []
    all_states = []

    with mp_pose.Pose(static_image_mode=False,
                      model_complexity=1,
                      enable_segmentation=False) as pose:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            # Convert BGR to RGB
            image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image.flags.writeable = False
            result = pose.process(image)
            image.flags.writeable = True

            if not result.pose_landmarks:
                continue

            landmarks = result.pose_landmarks.landmark
            feat = extract_feature_vector(landmarks)
            if feat is None:
                continue

            st = knee_state(landmarks)
            all_features.append(feat)
            all_states.append(st)

    cap.release()

    if len(all_features) == 0:
        print("No usable frames extracted.")
        return

    all_features = np.array(all_features)   # [T, 16]
    all_states = np.array(all_states, int)  # [T]

    # group features by state
    features_per_state = [[] for _ in range(NUM_STATES)]
    for x, s in zip(all_features, all_states):
        features_per_state[s].append(x.tolist())

    for s in range(NUM_STATES):
        if len(features_per_state[s]) == 0:
            print(f"State {s} has no frames; adjust thresholds.")
            return

    means, stds = fit_gaussians(features_per_state)
    trans = fit_transitions(all_states.tolist())
    prior = fit_prior(int(all_states[0]))

    log_prior = np.log(prior).tolist()
    log_trans = np.log(trans).tolist()

    # detect reps and compute per-rep log-likelihoods
    reps = segment_reps(all_states.tolist())
    if len(reps) == 0:
        print("No reps detected; treating whole clip as one rep.")
        reps = [(0, len(all_states) - 1)]

    rep_loglikes = []
    for (start, end) in reps:
        seq = all_features[start:end+1, :]
        _, ll = viterbi_loglik(seq,
                               np.array(log_prior),
                               np.array(log_trans),
                               means, stds)
        rep_loglikes.append(ll)

    rep_loglikes = np.array(rep_loglikes)
    mean_ll = float(rep_loglikes.mean())
    std_ll = float(rep_loglikes.std() if rep_loglikes.size > 1 else 1.0)

    threshold_sigma = 2.0  # tune later if needed

    model = {
        "numStates": NUM_STATES,
        "numFeatures": NUM_FEATURES,
        "logPrior": log_prior,
        "logTrans": log_trans,
        "emissions": [
            {
                "means": means[s],
                "stds": stds[s],
            }
            for s in range(NUM_STATES)
        ],
        "meanLogLikelihood": mean_ll,
        "stdLogLikelihood": std_ll,
        "thresholdSigma": threshold_sigma,
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(model, f, indent=2)

    print(f"Saved HMM model to {OUTPUT_JSON}")
    print(f"Reps detected: {len(reps)}")
    print(f"Mean log-likelihood: {mean_ll:.2f}, std: {std_ll:.2f}")


if __name__ == "__main__":
    main()
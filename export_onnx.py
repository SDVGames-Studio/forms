#!/usr/bin/env python3
"""Export the final SB3 PPO checkpoint to a deterministic ONNX policy (#502).

Stable-Baselines3 ships no native ONNX export, so this follows the documented
pattern: wrap ``model.policy`` in a small ``torch.nn.Module`` whose ``forward``
calls the policy with ``deterministic=True`` (argmax per MultiDiscrete head),
then export with ``torch.onnx.export`` at opset 17. Only the actor/policy
network is exported — the value head is not part of the graph.

    python export_onnx.py \
        --model runs/issue471_check/final_model.zip \
        --vecnormalize runs/issue471_check/vecnormalize.pkl \
        --out models/policy.onnx

The ONNX graph takes ONE flat tensor named "input" with shape
(1, OBS_SIZE) and produces the deterministic action named "action"
(one argmax per action head). The tensor names are stable on purpose —
the Phase 7 ncnn wrapper (pnnx + NcnnAIController2D) references them.

Normalization contract (DEPLOYMENT.md §3): the policy was trained behind
SB3's VecNormalize, so it expects NORMALIZED observations. The
normalization is NOT baked into the graph — the game replays it at
runtime via the ``obs_norm_stats_path`` sidecar. This script loads the
run's ``vecnormalize.pkl`` only to build a *normalized* dummy input for
the export/parity checks, exactly the way inference will see it.

Definition of Done (issue #502): a valid .onnx exists,
``onnx.checker.check_model`` passes, and onnxruntime output for the dummy
input matches the PyTorch ``deterministic=True`` output (discrete argmax
actions must match exactly).

Arguments:
  --model         SB3 PPO checkpoint (Phase 6 final artifact:
                  <experiment_dir>/final_model.zip).
  --vecnormalize  matching VecNormalize statistics; omit (or pass an empty
                  string) to skip normalization of the dummy input (models
                  trained without VecNormalize only).
  --out           output .onnx path (default models/policy.onnx).
  --logits-out    ALSO export the pre-argmax LOGITS graph (ncnn deployment
                  variant, #505) to this path. The bundled NcnnRunner
                  GDExtension statically links ncnn WITHOUT the ArgMax
                  layer, so the .ncnn.param converted from --out (argmax
                  baked in) can never load ("layer ArgMax not exists or
                  registered"). Deployed ncnn models therefore export the
                  per-head MultiDiscrete logits ("action_net" output,
                  heads concatenated: 3+8+6+4 = 21) and the argmax runs
                  caller-side (NcnnRunner.run_discrete_action /
                  InferenceMath.argmax per head) — the upstream
                  godot-native-rl convention. Verified here: per-head
                  argmax of the logits graph must equal the deterministic
                  actions of the --out reference graph on the dummy obs.
  --opset         ONNX opset version (default 17).
  --seed          RNG seed for the dummy observation (default 0 — the
                  whole run is deterministic and reproducible).
"""

import argparse
import os
import pathlib
import pickle

import numpy as np
import onnx
import onnxruntime as ort
import torch
from stable_baselines3 import PPO

INPUT_NAME = "input"
OUTPUT_NAME = "action"
LOGITS_OUTPUT_NAME = "logits"


class DeterministicOnnxPolicy(torch.nn.Module):
    """Feed the policy a single flat obs tensor, return deterministic actions.

    The environment exposes a single-key dict observation ``{"obs": Box}``
    (OBSERVATION_SPEC.md — the trainer reads exactly one key, "obs"), so the
    wrapper rebuilds that dict from the flat tensor. This keeps the ONNX
    interface a single tensor named "input" instead of a nested dict graph.
    """

    OBS_KEY = "obs"  # single-key dict contract (OBSERVATION_SPEC.md)

    def __init__(self, policy):
        super().__init__()
        self.policy = policy
        self.policy.set_training_mode(False)

    def forward(self, obs: torch.Tensor) -> torch.Tensor:
        # BasePolicy.forward returns (actions, values, log_prob); the ONNX
        # graph exports only the deterministic actions head.
        actions, _, _ = self.policy({self.OBS_KEY: obs}, deterministic=True)
        return actions


class LogitsOnnxPolicy(torch.nn.Module):
    """Pre-argmax deployment head: the flat per-head MultiDiscrete logits.

    Replays the actor pipeline of ``policy.get_distribution`` (features ->
    mlp_extractor.forward_actor -> action_net); for a MultiDiscrete policy its
    output is the heads' logits concatenated in order — everything the argmax
    wrapper computes its deterministic actions FROM, minus the ArgMax ops that
    ncnn's NcnnRunner build cannot load (see --logits-out in the module
    docstring). Consumers argmax per head (InferenceMath.argmax /
    run_discrete_action). (SB3 2.4 exposes no flat ``.logits`` on
    MultiCategoricalDistribution, hence the explicit pipeline.)
    """

    OBS_KEY = "obs"  # single-key dict contract (OBSERVATION_SPEC.md)

    def __init__(self, policy):
        super().__init__()
        self.policy = policy
        self.policy.set_training_mode(False)

    def forward(self, obs: torch.Tensor) -> torch.Tensor:
        features = self.policy.extract_features({self.OBS_KEY: obs})
        latent_pi = self.policy.mlp_extractor.forward_actor(features)
        return self.policy.action_net(latent_pi)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--model", default="runs/issue471_check/final_model.zip",
                        help="SB3 PPO checkpoint (final_model.zip of an experiment)")
    parser.add_argument("--vecnormalize", default=None,
                        help="matching vecnormalize.pkl; '' disables normalization")
    parser.add_argument("--out", default="models/policy.onnx", help="output .onnx path")
    parser.add_argument("--logits-out", default="", dest="logits_out",
                        help="also export the pre-argmax logits graph "
                             "(ncnn deployment variant, #505) to this path")
    parser.add_argument("--opset", type=int, default=17, help="ONNX opset version")
    parser.add_argument("--seed", type=int, default=0, help="seed for the dummy obs")
    args = parser.parse_args()
    if args.vecnormalize is None:
        sidecar = pathlib.Path(args.model).with_name("vecnormalize.pkl")
        args.vecnormalize = str(sidecar) if sidecar.exists() else ""
    return args


def load_obs_normalizer(path: str):
    """Load VecNormalize observation statistics (obs_rms only, no env needed).

    For a dict observation space SB3 stores ``obs_rms`` as a dict keyed by
    observation key; the Forms contract has exactly one key, "obs".
    """
    with open(path, "rb") as fh:
        vec_normalize = pickle.load(fh)
    obs_rms = vec_normalize.obs_rms
    if isinstance(obs_rms, dict):
        if set(obs_rms) != {"obs"}:
            raise SystemExit(f"unexpected obs keys {sorted(obs_rms)}; expected ['obs']")
        obs_rms = obs_rms["obs"]
    return obs_rms, vec_normalize.clip_obs, vec_normalize.norm_obs, vec_normalize.epsilon


def main() -> int:
    args = parse_args()
    if not os.path.exists(args.model):
        raise SystemExit(f"checkpoint not found: {args.model}")
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    model = PPO.load(args.model, device="cpu")
    policy = model.policy
    obs_space = model.observation_space["obs"]
    obs_size = int(obs_space.shape[-1])
    n_heads = [int(n) for n in model.action_space.nvec]
    print(f"loaded {args.model}: obs {obs_space}, action MultiDiscrete({n_heads})")

    # Deterministic dummy observation drawn from the RAW observation space,
    # then normalized exactly like inference-time replay (if stats provided).
    dummy_raw = np.random.uniform(obs_space.low, obs_space.high, size=(1, obs_size))
    if args.vecnormalize:
        if not os.path.exists(args.vecnormalize):
            raise SystemExit(f"vecnormalize stats not found: {args.vecnormalize}")
        rms, clip_obs, norm_obs, epsilon = load_obs_normalizer(args.vecnormalize)
        if not norm_obs:
            print("note: vecnormalize has norm_obs=False; exporting raw obs input")
        else:
            dummy = np.clip((dummy_raw - rms.mean) / np.sqrt(rms.var + epsilon),
                            -clip_obs, clip_obs)
            print(f"normalized dummy obs via {args.vecnormalize} "
                  f"(clip_obs={clip_obs}, count={rms.count:.0f})")
    else:
        dummy = dummy_raw
        print("no VecNormalize stats; using raw dummy obs (model trained unnormalized)")
    dummy = dummy.astype(np.float32)

    wrapper = DeterministicOnnxPolicy(policy).eval()
    with torch.no_grad():
        torch_actions = wrapper(torch.from_numpy(dummy)).numpy()
    print(f"pytorch deterministic action for dummy obs: {torch_actions.tolist()}")

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    export_kwargs = dict(
        input_names=[INPUT_NAME],
        output_names=[OUTPUT_NAME],
        opset_version=args.opset,
        dynamic_axes=None,  # fixed (1, OBS_SIZE) batch — ncnn runs single obs
    )
    try:  # torch >= 2.6: force the legacy (traced) exporter — dynamo traces
        # the SB3 policy graph poorly and its graph names are unstable.
        torch.onnx.export(wrapper, (torch.from_numpy(dummy),), args.out,
                          dynamo=False, **export_kwargs)
    except TypeError:  # older torch without the `dynamo` kwarg
        torch.onnx.export(wrapper, (torch.from_numpy(dummy),), args.out, **export_kwargs)
    print(f"exported {args.out} (opset {args.opset}, "
          f"input '{INPUT_NAME}' (1,{obs_size}) -> output '{OUTPUT_NAME}')")

    # --- Definition of Done checks -------------------------------------
    onnx_model = onnx.load(args.out)
    onnx.checker.check_model(onnx_model)
    graph_in = onnx_model.graph.input[0].name
    graph_out = onnx_model.graph.output[0].name
    assert graph_in == INPUT_NAME and graph_out == OUTPUT_NAME, (
        f"graph tensor names drifted: in={graph_in!r} out={graph_out!r}")

    session = ort.InferenceSession(args.out, providers=["CPUExecutionProvider"])
    ort_actions = session.run(None, {INPUT_NAME: dummy})[0]
    ort_actions = np.asarray(ort_actions).reshape(torch_actions.shape)
    matches = np.array_equal(ort_actions, torch_actions)
    max_diff = float(np.max(np.abs(ort_actions.astype(np.int64) - torch_actions.astype(np.int64))))
    print(f"onnxruntime action: {ort_actions.tolist()}")
    print(f"parity: exact match={matches} (max abs diff {max_diff}; "
          f"discrete argmax actions must match exactly)")

    if not matches:
        raise SystemExit("VERIFICATION FAILED: ONNX and PyTorch actions differ")
    print("VERIFICATION OK: valid ONNX, checker passed, onnxruntime matches "
          "PyTorch deterministic output")

    # --- ncnn deployment variant: pre-argmax logits graph (#505) --------
    if args.logits_out:
        logits_wrapper = LogitsOnnxPolicy(policy).eval()
        with torch.no_grad():
            torch_logits = logits_wrapper(torch.from_numpy(dummy)).numpy()
        assert torch_logits.shape == (1, sum(n_heads)), (
            f"logits shape {torch_logits.shape} != (1, {sum(n_heads)})")
        os.makedirs(os.path.dirname(args.logits_out) or ".", exist_ok=True)
        try:
            torch.onnx.export(logits_wrapper, (torch.from_numpy(dummy),), args.logits_out,
                              dynamo=False, input_names=[INPUT_NAME],
                              output_names=[LOGITS_OUTPUT_NAME],
                              opset_version=args.opset, dynamic_axes=None)
        except TypeError:  # older torch without the `dynamo` kwarg
            torch.onnx.export(logits_wrapper, (torch.from_numpy(dummy),), args.logits_out,
                              input_names=[INPUT_NAME],
                              output_names=[LOGITS_OUTPUT_NAME],
                              opset_version=args.opset, dynamic_axes=None)
        onnx.checker.check_model(onnx.load(args.logits_out))
        logits_session = ort.InferenceSession(args.logits_out, providers=["CPUExecutionProvider"])
        ort_logits = logits_session.run(None, {INPUT_NAME: dummy})[0]
        logits_close = np.allclose(ort_logits, torch_logits, atol=1e-4)
        # Per-head argmax of the logits must reproduce the reference actions:
        # the caller-side selection the deployed ncnn model relies on.
        splits, ofs, argmaxes = [], 0, []
        for n in n_heads:
            splits.append(ort_logits[0, ofs:ofs + n])
            argmaxes.append(int(splits[-1].argmax()))
            ofs += n
        argmax_match = argmaxes == [int(a) for a in np.ravel(torch_actions)]
        print(f"exported {args.logits_out} (logits (1,{sum(n_heads)}), "
              f"per-head argmax {argmaxes})")
        print(f"logits parity: ort-vs-torch close={logits_close}, "
              f"argmax-vs-reference match={argmax_match}")
        if not (logits_close and argmax_match):
            raise SystemExit("VERIFICATION FAILED: logits variant drift")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

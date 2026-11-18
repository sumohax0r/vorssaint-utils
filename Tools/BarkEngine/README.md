# Local Bark Clean runtime

Bark 3.0 Clean is an English speech model that removes fillers and repeats.
It uses a separate Python 3.11 / MLX worker in this local prototype. Python 3.11
must remain installed at the path used by `setup.sh` (Homebrew by default).
The virtual environment lives in `~/Library/Application Support/VorssaintBarkRuntime/`.
The build/repatch scripts install its pinned dependencies; no model weights are
fetched or loaded by the build. This environment is shared by local rebuilds.

Selecting Bark Clean downloads about 180 MB of pinned model/configuration files.
First dictation converts the published weights to a 4-bit MLX cache inside that
model directory, requiring additional disk for the prepared weights and potentially about
6 GB of transient RAM according to the reference loader. Preparation is atomic,
with a ten-minute startup timeout. Interrupted caches are discarded on retry.
Remove download removes the model and expanded cache; Unload from memory ends
the worker. The small shared Python environment remains installed for reuse.

The worker shares the existing per-user model lock, exits if its parent exits,
and uses the existing JSON pipe protocol and resource monitoring. It captures no
audio. Hugging Face offline mode is enabled during loading/inference. It adds no
leading silence, following Clean's evaluated configuration. Long recordings are
processed in pieces of at most 30 seconds, choosing a quiet boundary in the final
five seconds. This bounds inference input memory; chunk boundaries may affect
accuracy. Live preview uses the app's existing periodic full-snapshot decoding.

## Attribution

`bark_loader.py` and `bark_mlx.py` are unmodified reference loaders from Conway
Research, repository `ConwayResearch/Underdog-Bark-3.0-Clean`, revision
`6d34ed8639b2b9a33e764acf06748519bbb950cf`. Model/repository license: CC BY 4.0.
See NOTICE and https://creativecommons.org/licenses/by/4.0/.
Source: https://huggingface.co/ConwayResearch/Underdog-Bark-3.0-Clean

Vorssaint's wrapper uses the published 4-bit affine quantization option and changes cache location,
cache completion handling, process lifetime, and long-recording segmentation.
The weights are requantized, without fine-tuning. Accuracy and speed may differ
from the published FP16 results. After conversion the worker replaces its own
process before loading, releasing conversion allocations. After a successful
4-bit load, the obsolete FP16 cache is removed. A low steady-state RAM target
has not yet been measured; download size is not a RAM estimate.

MLX and mlx-audio use the MIT license. Installed dependencies retain their
individual licenses in their Python package metadata. Requirements pin the full
resolved environment; `setup.sh` also records installed versions in that runtime.

Integration was built locally. Recognition quality, first-use conversion, and
actual memory use still need speech verification; no model was predownloaded.

## Phonon 2.5 English

`phonon_worker.py` adapts Fermion Research's pinned `fermion-research==0.2.13`
MLX runtime to the same local worker protocol. It uses the published
`five-value-25-en` profile and default runtime decode settings. The app downloads
and verifies the pinned archive; the worker only unpacks that archive into a
`prepared/` folder inside the managed model directory. It never fetches models.
Remove download deletes the archive and prepared files together. The existing
single-worker lock and parent watchdog also apply to Phonon. Runtime dependencies
reuse the pinned MLX stack; the adapter package is installed without its optional
CPU/Torch dependency stack. First loading can compile Metal kernels.

Model: https://huggingface.co/FermionResearch/Phonon-2.5-English
Weights: CC-BY-4.0; publisher code: Apache-2.0.

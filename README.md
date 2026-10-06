# onnx2novaic-98539-dist

Public release mirror for the private `onnx2novaic-98539` repository.

It exists for one reason: the NT98539A board this project targets cannot
authenticate to GitHub. A private release asset has to be fetched through the
API by asset id, with a token — and this board's `curl` is built without TLS
(`Protocols: file ftp http tftp`), so that path is closed. A public release
asset is a plain redirect to storage, which the board *can* follow, because
`/bin/openssl` is a full OpenSSL 3.5 even though no HTTP client on the device
can use it.

## What is here

Release [`v1`](../../releases/tag/v1):

| | |
|---|---|
| `ai3_bench` | aarch64 benchmark: times `vendor_ai3_net_proc()` on a converted NPU model |
| `https_get.sh` | fetches an https URL using `openssl s_client`, since no client on the board has TLS |
| `fetch_board.sh` | pulls these assets onto the board; needs no credentials |

Not here, and not going to be: source, the Novaic SDK, ONNX models, training
data, or anything carrying customer weights.

## Using it on the board

```sh
# once: fetch the two scripts (no credentials needed)
wget -q -O https_get.sh   http://<your-host>/https_get.sh   # or copy them over
wget -q -O fetch_board.sh http://<your-host>/fetch_board.sh
chmod +x *.sh

# once: install a CA bundle. The board has OpenSSL but ships no trust store,
# so this fetches one unverified and checks it against a pinned sha256.
sh fetch_board.sh --bootstrap

# from then on
sh fetch_board.sh ai3_bench
./ai3_bench <model>.bin --cfg-model-info 1 --expect-input 128x32x3 \
  --plugin-cpu -1 --warmup 3 --iters 30
```

The two scripts are the bootstrap problem: fetching them needs something that
can already fetch. Copy them over once by whatever means the board has — a
share, a serial paste, a local HTTP server — and everything after that is
self-service.

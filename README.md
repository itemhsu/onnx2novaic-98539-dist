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

Release [`v1`](../../releases/tag/v1), overwritten by CI on every run:

| | |
|---|---|
| `ai3_bench` | aarch64 benchmark: times `vendor_ai3_net_proc()` on a converted NPU model |
| `https_get.sh` | fetches an https URL using `openssl s_client`, since no client on the board has TLS |
| `fetch_board.sh` | pulls these assets onto the board; needs no credentials |
| `nvt_model-latest.bin` | the most recent converted NPU model, whatever it was |
| `nvt_model-<chip>-opmode<N>-<run>.bin` | the same model under a name that traces back to the conversion that produced it |

`nvt_model-latest.bin` is a rolling alias and says nothing about which chip or
options produced it — use the run-numbered name when that matters.

Not here, and not going to be: source, the Novaic SDK, float ONNX models, or
training data.

---

# Step by step on the board

Everything below was run on an NT98539A (`Novatek NS02302`, aarch64 Cortex-A53,
Linux 6.12.57, Buildroot glibc 2.39, 360 MB RAM). The outputs are real.

## 1. Get the two scripts onto the board

This is the one step that cannot bootstrap itself: fetching needs something
that can already fetch. Nothing here needs credentials — the two files just
have to arrive.

**Every block says which machine it runs on.** `host$` is a host shell,
`board#` is the board.

### The board can do it alone

No share, no server, no host. `/bin/openssl` is a full OpenSSL even though no
HTTP client on the device can use TLS, so paste this:

```console
board# mkdir -p /tmp/lab && cd /tmp/lab
board# for f in https_get.sh fetch_board.sh; do
>   printf "GET /itemhsu/onnx2novaic-98539-dist/main/$f HTTP/1.1\r\nHost: raw.githubusercontent.com\r\nConnection: close\r\n\r\n" \
>   | openssl s_client -quiet -connect raw.githubusercontent.com:443 \
>       -servername raw.githubusercontent.com 2>/dev/null > /tmp/r.$$
>   n=$(sed -n 's/^Content-Length: *//p' /tmp/r.$$ | tr -d '\r' | head -1)
>   tail -c "$n" /tmp/r.$$ > $f && rm -f /tmp/r.$$
> done
board# chmod +x *.sh && ls
fetch_board.sh  https_get.sh
```

`tail -c $content_length` rather than looking for the end of the headers:
busybox `grep` has no `-b`, so there is no byte offset to be had, and `sed` and
`awk` are not safe on binary. `raw.githubusercontent.com` always sends a
`Content-Length` and never redirects, which is why this is four lines and not
forty.

**This first fetch is not verified** — there is no trust store on the board
yet, which is the next step. Once step 2 has installed one, you can confirm
what you got:

```console
board# sh fetch_board.sh https_get.sh   verified_https_get.sh
board# sh fetch_board.sh fetch_board.sh verified_fetch_board.sh
board# cmp https_get.sh verified_https_get.sh && cmp fetch_board.sh verified_fetch_board.sh \
>   && echo "both match a verified fetch"
```

### Or hand them over, if that is easier

Download them on any machine and move them across by whatever the board has —
a share, an SD card, a plain-HTTP server. The board's busybox `wget` has no
TLS but is perfectly happy with `http://`:

```console
host$ mkdir -p /tmp/serve && cd /tmp/serve
host$ base=https://raw.githubusercontent.com/itemhsu/onnx2novaic-98539-dist/main
host$ curl -sfLO $base/fetch_board.sh
host$ curl -sfLO $base/https_get.sh
host$ python3 -m http.server 8000      # address: ip -4 addr, or hostname -I
```

```console
board# mkdir -p /tmp/lab && cd /tmp/lab
board# wget -q http://192.168.1.50:8000/fetch_board.sh
board# wget -q http://192.168.1.50:8000/https_get.sh
board# chmod +x *.sh
```

Replace `192.168.1.50` with that machine's address.

### Either way

Keep both files in the same directory and work from there: `fetch_board.sh`
looks for `https_get.sh` beside itself. Nothing below needs the host again.

Both routes were run as written on an NT98539A from an empty `/tmp/lab`,
through to a timing figure.

## 2. Install a CA bundle, once

The board has OpenSSL but ships no trust store — `/etc/openssl` holds a config
and no certificates.

```console
board# sh fetch_board.sh --bootstrap
```

```
/tmp/cacert.14161  188900 bytes
installed /etc/ssl/cacert.pem (188900 bytes, hash verified)
```

This fetch is **unverified** — at that point there is nothing to verify
against — so the bundle is checked against a `sha256` pinned inside
`fetch_board.sh` before being installed. If it does not match, nothing is
installed and you are told why. The usual cause is the bundle being refreshed
upstream: take the current hash from <https://curl.se/docs/caextract.html> and
update `CA_SHA256`.

Everything after this is verified. A bad certificate is refused:

```console
board# sh https_get.sh https://expired.badssl.com/ /dev/null
```
```
https_get: connection to expired.badssl.com failed (certificate? try --insecure to test)
```

## 3. See what is available

```console
board# sh fetch_board.sh --list
```

```
ai3_bench
fetch_board.sh
https_get.sh
nvt_model-539A-opmode2-6.bin
nvt_model-latest.bin
```

## 4. Fetch the tool and a model

```console
board# sh fetch_board.sh ai3_bench
board# sh fetch_board.sh nvt_model-latest.bin model.bin
```

```
ai3_bench  72904 bytes
model.bin  22771400 bytes
```

Both are byte-identical to what CI built — compare `md5sum` against the
checksums in the workflow run if you want to be sure.

## 5. Approach the NPU one stage at a time

`ai3_bench` runs in stages, and `--stage N` stops after stage N. Only stage 6
makes the NPU read a physical address the program chose, so there is no reason
to go there before the earlier stages agree with expectations.

**Stage 3 — what does the model want?** Queries only; the NPU is not started.

```console
board# ./ai3_bench model.bin --cfg-model-info 1 --plugin-cpu -1 --stage 3
```

```
model model.bin, 22771400 bytes, magic NVT3
[1] hd_common_init / hd_common_mem_init / vendor_ai3_dev_init
HDAL: Version: v3.500.1
    pool: 8 x 23855104 bytes (182.0 MB total)
    ok
[2] load model into an hdal block
    model      pa=0x18011000 va=0x7fb35b7000 size=22771400
    loaded, cache flushed
[3] dev_get(cfg_id=1) for the work-buffer sizes
    proc_mem.buf[0].size = 344128
    proc_mem.buf[1].size = 536576
    ...
    type=0 attr=0 ctrl=0, 2 buffer(s) requested
```

**Stage 5 — what shapes does it declare?** Opens the network and reads its
input and output descriptions. Still no inference.

```console
board# ./ai3_bench model.bin --cfg-model-info 1 --plugin-cpu -1 --stage 5
```

```
[5] net_start, then net_get each path
  in  path=1879048192
     w=128 h=32 c=3 n=1 t=0 fmt=0x23180888 size=0 layout= scale=1 zp=0 name=image
       line_ofs=128 channel_ofs=4096 batch_ofs=12288 size_real=0
  out path=2952790018
     w=1 h=384 c=128 n=1 t=1 fmt=0xa110010e size=98304 layout=whcn
     scale=0.90977 zp=65102 name=LayerNormalization_memory_Y
       line_ofs=2 channel_ofs=768 batch_ofs=98304 size_real=0
```

Read this carefully — it is the only honest check that the tool and the model
agree. `name=image` and `128 x 32 x 3` are the model's own input; the strides
say the input is **planar** 8-bit (`line_ofs` = width, `channel_ofs` = one
whole plane).

## 6. Time it

```console
board# ./ai3_bench model.bin --cfg-model-info 1 --expect-input 128x32x3 \
         --plugin-cpu -1 --warmup 3 --iters 20
```

```
    input shape matches 128x32x3 -- layout confirmed, safe to run
[6] allocate I/O, net_set, time net_proc
    in0        pa=0x1c514000 va=0x7fb149c000 size=77824
    out0       pa=0x1dc15000 va=0x7fb1474000 size=163840
    warmup 3
    timing 20 iterations

== net_proc over 20 iterations
   min      11.030 ms
   median   11.070 ms
   mean     11.077 ms
   max      11.143 ms
   out[0] first 16 bytes: f7 fd 74 f4 ce ff 91 f2 d9 02 a8 f9 d1 08 1c ff
```

**`--expect-input` is a gate, not decoration.** Without it the run says so, and
with a value the model does not report the run stops before the NPU is handed
any address. Use it.

`--plugin-cpu -1` skips the CPU engine. Supply it when the model compiles to
NPU layers only; without it, `vendor_ai_cpu1_get_engine` pulls in
`libprebuilt_ai`.

The last line matters: a run that times a no-op would print zeros there.

## 7. Many inputs at once

To push a whole evaluation set through and keep every output, write one raw
input file per sample and list them:

```console
board# ./ai3_bench model.bin --cfg-model-info 1 --expect-input 128x32x3 \
         --plugin-cpu -1 --batch list.txt --batch-in inputs --batch-out outputs
```

Each input is raw bytes in the layout stage 5 reported — for the model above,
planar 8-bit, R plane then G then B, `128*32*3 = 12288` bytes. Each output is
written as `<name>.out`, raw `int16`.

Dequantise with the figures the tool printed:

```
real = (raw - zero_point) * scale_ratio / 2**14
```

`scale_ratio` is declared `FLOAT` in the SDK's buffer struct and is not one —
it carries the scale in Q14. Treating `0.90977` as the scale rather than
`0.90977 / 16384` is wrong by a factor of 16,384, and it is a quiet error:
greedy decoding is nearly invariant to a uniform scale on the output, so it
still almost works. The authoritative figures are in `quant_input_output.json`
from the conversion that produced the model.

## Detached runs

A long run started over telnet dies when the session closes. Detach it:

```console
board# nohup sh -c './ai3_bench ... > run.log 2>&1; echo done > run.done' >/dev/null 2>&1 &
```

## Troubleshooting

| what you see | what it means |
|---|---|
| `curl: (1) Protocol "https" not supported` | the board's curl has no TLS; that is why `https_get.sh` exists |
| `wget: error getting response: Connection reset by peer` on `:443` | busybox wget has no TLS either |
| `no CA bundle at /etc/ssl/cacert.pem` | run `sh fetch_board.sh --bootstrap` |
| `CA bundle hash mismatch` | the bundle changed upstream, or something tampered with it. Nothing was installed |
| `symbol lookup error: ... undefined symbol: vendor_common_mem_cache_sync` | a vendor library is missing from the device; `ai3_bench` expects the stock `/usr/lib` |
| `get_block(..., N bytes) failed` | the hdal pool ran dry. Each allocation takes a whole block; raise `--pool-blocks` |
| `please set 1 output buf` | internal to `ai3_bench`; each `net_proc` consumes the binding and it re-binds every iteration |
| `layer_cnt=0` | expected on this runtime: it fills `in_buf_cnt` and `out_buf_cnt` but not the job counts. The shape check is the real gate |
| `NT98539A does not support --op-mode 3` | this part is single-core; the graph modes are for the multi-core NN30 parts |

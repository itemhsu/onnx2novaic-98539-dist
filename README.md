# onnx2novaic-98539-dist

Public release mirror for the private `onnx2novaic-98539` repository. It exists
so the NT98539A board can fetch its own artifacts: that device cannot
authenticate to GitHub, because its `curl` is built without TLS
(`Protocols: file ftp http tftp`), and a private asset has to be fetched
through the API by asset id with a token. A public asset does not.

---

# Three steps on the board

Nothing else needed — no share, no server, no host, no credentials. Every block
is one line, meant to be copied as-is.

## 1. Bootstrap

Fetches the two helper scripts and installs a CA bundle.

```sh
mkdir -p /tmp/lab && cd /tmp/lab && for f in https_get.sh fetch_board.sh; do printf "GET /itemhsu/onnx2novaic-98539-dist/main/%s HTTP/1.1\r\nHost: raw.githubusercontent.com\r\nConnection: close\r\n\r\n" $f | openssl s_client -quiet -connect raw.githubusercontent.com:443 -servername raw.githubusercontent.com 2>/dev/null > /tmp/r; n=$(sed -n "s/^Content-Length: *//p" /tmp/r | tr -d "\r" | head -1); tail -c $n /tmp/r > $f; done; rm -f /tmp/r; chmod +x *.sh && sh fetch_board.sh --bootstrap
```

Output:

<pre>
installed /etc/ssl/cacert.pem (188900 bytes, hash verified)
</pre>

Stay in `/tmp/lab`: `fetch_board.sh` looks for `https_get.sh` beside itself.

## 2. Fetch the tool and a model

```sh
sh fetch_board.sh ai3_bench && sh fetch_board.sh nvt_model-latest.bin model.bin
```

Output:

<pre>
ai3_bench  72904 bytes
  [#########...........]  46%  10514186 / 22771400 bytes
model.bin  22771400 bytes
</pre>

The model is 21 MB and `openssl s_client` is not fast, so that takes a minute
or two. The bar is there so a quiet terminal is not mistaken for a hang — it
only appears when stderr is a terminal, so a redirected or `nohup`ed run keeps
a clean log.

## 3. Run it

```sh
./ai3_bench model.bin --cfg-model-info 1 --expect-input 128x32x3 --plugin-cpu -1 --warmup 3 --iters 20
```

Output:

<pre>
== net_proc over 20 iterations
   min      11.007 ms
   median   11.069 ms
   mean     11.060 ms
   max      11.176 ms
   out[0] first 16 bytes: f7 fd 74 f4 ce ff 91 f2 d9 02 a8 f9 d1 08 1c ff
</pre>

That is it.

`--expect-input` is a gate, not decoration: given a shape the model does not
report, the run stops before the NPU is handed anything. `--plugin-cpu -1`
skips the CPU engine, which this model does not need.

---

# What is in the release

| | |
|---|---|
| `ai3_bench` | aarch64 benchmark: times `vendor_ai3_net_proc()` on a converted NPU model |
| `https_get.sh` | fetches an https URL using `openssl s_client`, since no client on the board has TLS |
| `fetch_board.sh` | pulls these assets onto the board |
| `nvt_model-latest.bin` | the most recent converted model, whatever it was |
| `nvt_model-<chip>-opmode<N>-<run>.bin` | the same model, named so it traces back to the conversion |

`sh fetch_board.sh --list` shows what is actually there. CI overwrites these on
every run, and `nvt_model-latest.bin` is a rolling alias that says nothing about
which chip or options produced it — use the run-numbered name when that matters.

The two scripts are tracked files here as well as release assets, so step 1 can
fetch them from `raw.githubusercontent.com` without following a redirect.

Not here, and not going to be: source, the Novaic SDK, float ONNX models, or
training data.

---

Beyond the three steps — inspecting a model before running it, pushing a whole
set of inputs through, dequantising the output, and what the errors mean — see
**[Going further](Going%20further.md)**.

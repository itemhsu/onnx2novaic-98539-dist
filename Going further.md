# Going further

Past the three steps in the [README](README.md). Same board, same `/tmp/lab`,
same conventions: a block tagged `sh` is something to run, and anything
labelled Output is not.

## Look before you run

`--stage N` stops after stage N. Stage 3 asks the model what memory it wants;
stage 5 opens it and reads the shapes. Neither starts an inference.

```sh
./ai3_bench model.bin --cfg-model-info 1 --plugin-cpu -1 --stage 5
```

Output:

<pre>
  in  path=1879048192
     w=128 h=32 c=3 n=1 t=0 fmt=0x23180888 size=0 layout= scale=1 zp=0 name=image
       line_ofs=128 channel_ofs=4096 batch_ofs=12288 size_real=0
  out path=2952790018
     w=1 h=384 c=128 n=1 t=1 fmt=0xa110010e size=98304 layout=whcn
     scale=0.90977 zp=65102 name=LayerNormalization_memory_Y
       line_ofs=2 channel_ofs=768 batch_ofs=98304 size_real=0
</pre>

This is the only honest check that the tool and the model agree about anything:
`name=image` and `128 x 32 x 3` are the model's own input, and the strides say
it is **planar** 8-bit — `line_ofs` is the width, `channel_ofs` is one plane.

## Many inputs at once

```sh
./ai3_bench model.bin --cfg-model-info 1 --expect-input 128x32x3 --plugin-cpu -1 --batch list.txt --batch-in inputs --batch-out outputs
```

`list.txt` holds one filename per line. Each input is raw bytes in the layout
stage 5 reported — planar 8-bit, R then G then B, `128*32*3 = 12288` bytes for
the model above. Each output is `<name>.out`, raw `int16`.

Dequantise with:

Output:

<pre>
real = (raw - zero_point) * scale_ratio / 2**14
</pre>

`scale_ratio` is declared `FLOAT` in the SDK's buffer struct and is not one: it
carries the scale in Q14. Using `0.90977` instead of `0.90977 / 16384` is wrong
by a factor of 16,384 and it is a quiet error — greedy decoding is nearly
invariant to a uniform scale on the output, so it still almost works. The
authoritative figures are in `quant_input_output.json` from the conversion.

## Long runs over telnet

They die when the session closes. Detach:

```sh
nohup sh -c './ai3_bench ... > run.log 2>&1; echo done > run.done' >/dev/null 2>&1 &
```

## Confirming the bootstrap

Step 1 fetches the scripts and the CA bundle before there is anything to verify
against. The bundle is checked against a `sha256` pinned in `fetch_board.sh`;
the scripts are not. Once a trust store is installed you can check them:

```sh
sh fetch_board.sh https_get.sh v1.sh && sh fetch_board.sh fetch_board.sh v2.sh && cmp https_get.sh v1.sh && cmp fetch_board.sh v2.sh && echo "both match a verified fetch"
```

And that a bad certificate is refused:

```sh
sh https_get.sh https://expired.badssl.com/ /dev/null
```

Output:

<pre>
https_get: connection to expired.badssl.com failed (certificate? try --insecure to test)
</pre>

## If step 1 cannot reach GitHub

Hand the files over instead. On any machine with TLS:

```sh
mkdir -p /tmp/serve && cd /tmp/serve && base=https://raw.githubusercontent.com/itemhsu/onnx2novaic-98539-dist/main && curl -sfLO $base/fetch_board.sh && curl -sfLO $base/https_get.sh && python3 -m http.server 8000
```

Then on the board, with `192.168.1.50` replaced by that machine's address
(`ip -4 addr`):

```sh
mkdir -p /tmp/lab && cd /tmp/lab && wget -q http://192.168.1.50:8000/fetch_board.sh && wget -q http://192.168.1.50:8000/https_get.sh && chmod +x *.sh && sh fetch_board.sh --bootstrap
```

Busybox `wget` has no TLS but is fine with `http://`. A share works the same
way. Note that steps 2 and 3 still reach GitHub through `https_get.sh`, so if
step 1 failed for a network reason rather than a TLS one, they will too.

---

# When something goes wrong

| what you see | what it means |
|---|---|
| `syntax error: unexpected "do"` | a multi-line paste arrived in pieces. Every block here is one line |
| `curl: (1) Protocol "https" not supported` | the board's curl has no TLS. That is why `https_get.sh` exists |
| `wget: error getting response: Connection reset by peer` on `:443` | busybox wget has no TLS either |
| `no CA bundle at /etc/ssl/cacert.pem` | step 1 did not finish; rerun its `--bootstrap` |
| `CA bundle hash mismatch` | the bundle changed upstream, or something tampered with it. Nothing was installed. Current hash: <https://curl.se/docs/caextract.html> |
| `no credentials` from `fetch.sh` | that is the *host* script from the private repository. On the board use `fetch_board.sh` |
| `symbol lookup error: ... vendor_common_mem_cache_sync` | a vendor library is missing; `ai3_bench` expects the stock `/usr/lib` |
| `get_block(..., N bytes) failed` | the hdal pool ran dry. Each allocation takes a whole block; raise `--pool-blocks` |
| `layer_cnt=0` | expected on this runtime: it fills `in_buf_cnt` and `out_buf_cnt` but not the job counts. The shape check is the real gate |
| `NT98539A does not support --op-mode 3` | this part is single-core; the graph modes are for the multi-core NN30 parts |

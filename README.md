
This is the repository for [8bitworkshop](https://github.com/sehugg/8bitworkshop/)'s
compiler tools, compiled with [Emscripten](https://emscripten.org/).

Only tested on Ubuntu.
Last tested with Emscripten 3.1.1 and 3.1.38 (though not very well)

![Build Status](https://github.com/sehugg/8bitworkshop-compilers/actions/workflows/all.js.yml/badge.svg)

Install Emscripten SDK:

https://emscripten.org/docs/getting_started/downloads.html

```
./emcc install latest
./emcc activate latest
. ./emsdk_env.sh
```

Install dependencies:
```
apt install libboost-graph-dev nasm bison flex texinfo zlib1g-dev
```

Init submodules:
```
git submodule init
git submodule update
```

Type "make"
```
make
```

Output files will be in `output/`



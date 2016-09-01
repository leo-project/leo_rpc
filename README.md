# leo_rpc - An RPC library for Erlang

An original rpc library, interface of which is similar to Erlang's RPC. Aim to connect with over 100 nodes.

## Usage
### Getting Started
#### Building `leo_rpc`

- Build `leo_rpc`, and set up two environment which are different with `listen_port` configurations

```bash
$ git clone https://github.com/leo-project/leo_rpc leo_rpc_0
$ cd leo_rpc_0
$ make
$ cd ../
$ cp -r leo_rpc_0 leo_rpc_1
$ cd leo_rpc_1
$ vi src/leo_rpc.app.src
##
## Edit 'listen_port' from 13075 to 13076
## {listen_port,    13076},
##
```

#### Launch two erlang-nodes with `erl`
- Launch `leo_rpc_0`

```bash
##
## Launch "leo_rpc_0"
##
$ cd leo_rpc_0
$ erl -pa ./ebin/ ./deps/*/ebin -name 'node_0@127.0.0.1'
Erlang/OTP 18 [erts-7.3] [source] [64-bit] [smp:8:8] [async-threads:10] [kernel-poll:false] [dtrace]

Eshell V7.3  (abort with ^G)
(node_0@127.0.0.1)1> application:start(leo_rpc).
ok
(node_0@127.0.0.1)2> leo_rpc:node().
'node_0@127.0.0.1'
(node_0@127.0.0.1)3> leo_rpc:nodes().
[]
(node_0@127.0.0.1)4> leo_rpc:port().
13075
```

- Launch `leo_rpc_1`

```bash
##
## Launch "leo_rpc_1"
##
$ cd leo_rpc_1
$ erl -pa ./ebin/ ./deps/*/ebin -name 'node_1@127.0.0.1'
Erlang/OTP 18 [erts-7.3] [source] [64-bit] [smp:8:8] [async-threads:10] [kernel-poll:false] [dtrace]

Eshell V7.3  (abort with ^G)
(node_1@127.0.0.1)1> application:start(leo_rpc).
ok
(node_1@127.0.0.1)2> leo_rpc:node().
'node_1@127.0.0.1'
(node_1@127.0.0.1)3> leo_rpc:nodes().
[]
(node_1@127.0.0.1)4> leo_rpc:port().
13076
```

#### Executing some leo_rpc's functions

```erlang
%% Execute rpc-call to a remote-node
(node_0@127.0.0.1)5> leo_rpc:call('node_1@127.0.0.1:13076', leo_rpc, node, []).
'node_1@127.0.0.1'
(node_0@127.0.0.1)6> leo_rpc:nodes().
[node_1]

%% Execute async rpc-call to a remote-node
(node_0@127.0.0.1)8> RPCKey = leo_rpc:async_call('node_1@127.0.0.1:13076', leo_rpc, node, []).
<0.252.0>
%% Get the value. (You have to type the following expression in 5 senconds after the above commands.)
(node_0@127.0.0.1)9> leo_rpc:nb_yield(RPCKey).
{value,'node_1@127.0.0.1'}

(node_0@127.0.0.1)11> leo_rpc:nodes().
[node_1]
(node_0@127.0.0.1)12> leo_rpc:status().
{ok,[{node_1,node_1,13076,0,4}]}
```

## License

leo_rpc's license is [Apache License Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

## Sponsors

LeoProject/LeoFS is sponsored by [Rakuten, Inc.](http://global.rakuten.com/corp/) and supported by [Rakuten Institute of Technology](http://rit.rakuten.co.jp/).

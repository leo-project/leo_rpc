# **leo_rpc**

An original rpc library, interface of which is similar to Erlang's RPC. Aim to connect with over 100 nodes.

## Usage

First clone the leo_rpc repository and create a copy of it.
Then, compile them with different 'listen_port' configurations.

```text
$ git clone https://github.com/leo-project/leo_rpc leo_rpc_0
$ cp -r leo_rpc_0 leo_rpc_1
$ cp -r leo_rpc_0 leo_rpc_2
$ cd leo_rpc_0
$ make
$ cd ../leo_rpc_1
$ vi src/leo_rpc.app.src
## Edit 'listen_port' from 13075 to 13076
         {listen_port,    13076},
$ make
$ cd ../leo_rpc_2
$ vi src/leo_rpc.app.src
## Edit 'listen_port' from 13075 to 13077
         {listen_port,    13077},
$ make
```

Then, start Erlang shells.

```text
$ cd leo_rpc_1
$ erl -pa ./ebin/ ./deps/*/ebin -name 'node_1@127.0.0.1'
Erlang R16B03-1 (erts-5.10.4) [source] [64-bit halfword] [smp:4:4] [async-threads:10] [kernel-poll:false]

Eshell V5.10.4  (abort with ^G)
(node_1@127.0.0.1)1> application:start(leo_rpc).
ok
(node_1@127.0.0.1)2> leo_rpc:node().
'node_1@127.0.0.1'
(node_1@127.0.0.1)3> leo_rpc:nodes().
[]
(node_1@127.0.0.1)4> leo_rpc:port().
13076
```

```text
$ cd leo_rpc_2
$ erl -pa ./ebin/ ./deps/*/ebin -name 'node_2@127.0.0.1'
Erlang R16B03-1 (erts-5.10.4) [source] [64-bit halfword] [smp:4:4] [async-threads:10] [kernel-poll:false]

Eshell V5.10.4  (abort with ^G)
(node_2@127.0.0.1)1> application:start(leo_rpc).
ok
(node_2@127.0.0.1)2> leo_rpc:node().
'node_2@127.0.0.1'
(node_2@127.0.0.1)3> leo_rpc:nodes().
[]
(node_2@127.0.0.1)4> leo_rpc:port().
13077
```

```text
$ cd leo_rpc_0
$ erl -pa ./ebin/ ./deps/*/ebin -name 'node_0@127.0.0.1'
Erlang R16B03-1 (erts-5.10.4) [source] [64-bit halfword] [smp:4:4] [async-threads:10] [kernel-poll:false]

Eshell V5.10.4  (abort with ^G)
(node_0@127.0.0.1)1> application:start(leo_rpc).
ok
(node_0@127.0.0.1)2> leo_rpc:node().
'node_0@127.0.0.1'
(node_0@127.0.0.1)3> leo_rpc:nodes().
[]
(node_1@127.0.0.1)4> leo_rpc:port().
13075
```
Then, we can try various rpc commands as follow.

```erl-sh
%% Execute rpc-call to a remote-node
(node_0@127.0.0.1)5> leo_rpc:call('node_1@127.0.0.1:13076', leo_rpc, node, []).
'node_1@127.0.0.1'
(node_0@127.0.0.1)6> leo_rpc:nodes().
[node_1]
(node_0@127.0.0.1)7> leo_rpc:call('node_2@127.0.0.1:13077', leo_rpc, node, []).
'node_2@127.0.0.1'

%% Execute async rpc-call to a remote-node
(node_0@127.0.0.1)8> RPCKey = leo_rpc:async_call('node_1@127.0.0.1:13076', leo_rpc, node, []).
<0.252.0>
%% Get the value. (You have to type the following expression in 5 senconds after the above commands.)
(node_0@127.0.0.1)9> leo_rpc:nb_yield(RPCKey).
{value,'node_1@127.0.0.1'}

%% Execute multi-call to plural nodes
(node_0@127.0.0.1)10> leo_rpc:multicall(['node_0@127.0.0.1:13075', 'node_1@127.0.0.1:13076', 'node_2@127.0.0.1:13077'], 'leo_date', 'clock', []).
{[1397709777556582,1397709777555220,1397709777555166],[]}

(node_0@127.0.0.1)11> leo_rpc:nodes().
[node_0,node_1,node_2]
(node_0@127.0.0.1)12> leo_rpc:status().
{ok,[{node_0,node_0,13075,4,4},
     {node_1,node_1,13076,4,4},
     {node_2,node_2,13077,4,4}]}
```

## License

leo_rpc's license is "Apache License Version 2.0"

## Sponsors

LeoProject/LeoFS is sponsored by [Rakuten, Inc.](http://global.rakuten.com/corp/) and supported by [Rakuten Institute of Technology](http://rit.rakuten.co.jp/).

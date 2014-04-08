# **leo_rpc**

An original rpc library, interface of which is similar to Erlang's RPC. Aim to connect with over 100 nodes.

## Usage

```erl-sh
%% Start "leo_rpc"
1> application:start(leo_rpc).

%% Execute rpc-call to a remote-node
2> leo_rpc:call('node_0@127.0.0.1', 'leo_misc', 'get_value', ['a',[{'a',1},{'b',2},{'c',3}], <<"DEFAULT">> ]).
1
3> leo_rpc:call('node_0@127.0.0.1', 'leo_misc', 'get_value', ['d',[{'a',1},{'b',2},{'c',3}], <<"DEFAULT">> ]).
<<"DEFAULT">>

%% Execute async rpc-call to a remote-node
5> RPCKey1 = leo_rpc:async_call('node_0@127.0.0.1', 'leo_misc', 'get_value', ['a',[{'a',1},{'b',2},{'c',3}], <<"123">> ]).
<0.138.0>
6> leo_rpc:nb_yield(RPCKey1).
{value,1}

%% Execute multi-call to plural nodes
7> leo_rpc:multicall(['node_0@10.0.101.1', 'node_1@10.0.101.2'], 'leo_date', 'clock', []).
{[1373550225871064, 1373550225871067],[]}

8> leo_rpc:status().
{ok,[{'node_0@127.0.0.1',"127.0.0.1",13075,0,8}]}

9> leo_rpc:node().
'node_0@127.0.0.1'

10> leo_rpc:nodes().
['node_0@10.0.101.1', 'node_1@10.0.101.2']

```

## License

leo_rpc's license is "Apache License Version 2.0"

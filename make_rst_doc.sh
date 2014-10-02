#!/bin/sh

rm -rf doc/rst && mkdir doc/rst
make doc
pandoc --read=html --write=rst doc/leo_rpc.html -o doc/rst/leo_rpc.rst
pandoc --read=html --write=rst doc/leo_rpc_client_conn.html -o doc/rst/leo_rpc_client_conn.rst
pandoc --read=html --write=rst doc/leo_rpc_client_manager.html -o doc/rst/leo_rpc_client_manager.rst
pandoc --read=html --write=rst doc/leo_rpc_client_utils.html -o doc/rst/leo_rpc_client_utils.rst
pandoc --read=html --write=rst doc/leo_rpc_protocol.html -o doc/rst/leo_rpc_protocol.rst
pandoc --read=html --write=rst doc/leo_rpc_server.html -o doc/rst/leo_rpc_server.rst
pandoc --read=html --write=rst doc/leo_rpc_server_listener.html -o doc/rst/leo_rpc_server_listener.rst

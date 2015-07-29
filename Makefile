.PHONY: deps test


REBAR := ./rebar
APPS = erts kernel stdlib sasl crypto compiler inets mnesia public_key runtime_tools snmp syntax_tools tools xmerl webtool
PLT_FILE = .leo_rpc_dialyzer_plt
DOT_FILE = leo_rpc.dot
CALL_GRAPH_FILE = leo_rpc.png

all:
	@$(REBAR) update-deps
	@$(REBAR) get-deps
	@$(REBAR) compile
	@$(REBAR) xref skip_deps=true
	@ERL_FLAGS="-name node_0@127.0.0.1" $(REBAR) eunit skip_deps=true
compile:
	@$(REBAR) compile skip_deps=true
xref:
	@$(REBAR) xref skip_deps=true
eunit:
	@ERL_FLAGS="-name node_0@127.0.0.1" $(REBAR) eunit skip_deps=true
check_plt:
	@$(REBAR) compile
	dialyzer --check_plt --plt $(PLT_FILE) --apps $(APPS)
build_plt:
	@$(REBAR) compile
	dialyzer --build_plt --output_plt $(PLT_FILE) -Wrace_conditions --apps $(APPS) deps/*/ebin
dialyzer:
	@$(REBAR) compile
	dialyzer --plt $(PLT_FILE) -r ebin/ --dump_callgraph $(DOT_FILE)
doc: compile
	@$(REBAR) doc
callgraph: graphviz
	dot -Tpng -o$(CALL_GRAPH_FILE) $(DOT_FILE)
graphviz:
	$(if $(shell which dot),,$(error "To make the depgraph, you need graphviz installed"))
clean:
	@$(REBAR) clean skip_deps=true
distclean:
	@$(REBAR) delete-deps
	@$(REBAR) clean

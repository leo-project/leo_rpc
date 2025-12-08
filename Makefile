.PHONY: deps test compile xref eunit dialyzer doc clean distclean

REBAR := rebar3
APPS = erts kernel stdlib sasl crypto compiler inets mnesia public_key runtime_tools snmp syntax_tools tools xmerl
PLT_FILE = .leo_rpc_dialyzer_plt
DOT_FILE = leo_rpc.dot
CALL_GRAPH_FILE = leo_rpc.png

all: compile xref eunit

compile:
	@$(REBAR) compile

xref:
	@$(REBAR) xref

eunit:
	@ERL_FLAGS="-name node_0@127.0.0.1" $(REBAR) eunit

check_plt:
	@$(REBAR) compile
	dialyzer --check_plt --plt $(PLT_FILE) --apps $(APPS)

build_plt:
	@$(REBAR) compile
	dialyzer --build_plt --output_plt $(PLT_FILE) --apps $(APPS) _build/default/lib/*/ebin

dialyzer:
	@$(REBAR) dialyzer

doc:
	@$(REBAR) edoc

callgraph: graphviz
	dot -Tpng -o$(CALL_GRAPH_FILE) $(DOT_FILE)

graphviz:
	$(if $(shell which dot),,$(error "To make the depgraph, you need graphviz installed"))

clean:
	@$(REBAR) clean

distclean:
	@rm -rf _build
	@$(REBAR) clean -a

.PHONY: deps test

REBAR := ./rebar
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
clean:
	@$(REBAR) clean skip_deps=true
distclean:
	@$(REBAR) delete-deps
	@$(REBAR) clean
qc:
	@$(REBAR) qc skip_deps=true


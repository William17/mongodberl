REBAR = ./rebar -j8

all: deps compile

compile: deps
	${REBAR} compile

deps:
	${REBAR} get-deps

clean:
	${REBAR} clean

generate: compile
	cd rel && ../${REBAR} generate -f

relclean:
	rm -rf rel/mongodberl

run: generate
	./rel/mongodberl/bin/mongodberl start

console: generate
	./rel/mongodberl/bin/mongodberl console

foreground: generate
	./rel/mongodberl/bin/mongodberl foreground

erl: compile
	erl -pa ebin/ -pa lib/*/ebin/ -s mongodberl

test:
	ERL_AFLAGS="-config rel/mongodberl/etc/app.config -mnesia dir \"'data/'\""  $(REBAR)  compile ct skip_deps=true

.PHONY: all deps test clean

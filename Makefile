NAME        := $(shell basename `go list`)
VERSION     := $(shell git tag -l "v*" | head -n 1)
REVISION    := $(shell git rev-parse --short HEAD)

GOVERSION   := 1.10.3
OS          := windows darwin linux # darwin dragonfly freebsd linux netbsd openbsd plan9 solaris windows
ARCH        := amd64 386 # 386 amd64 arm arm64 ppc64 ppc64le mips64 mips64le
LDFLAGS     := -ldflags "-s -w -X \"main.Version=$(VERSION)\" -X \"main.Revision=$(REVISION)\""

GOPATH      := $(shell go env GOPATH)
SOURCE      := $(shell go list -f '{{$$d:=.Dir}}{{range .GoFiles}}{{$$d}}/{{.}}{{"\n"}}{{end}}' ./...)
OUTPUT      := build

.PHONY: build
build: $(OUTPUT)/$(NAME) ;

$(OUTPUT)/$(NAME): $(SOURCE) $(GOPATH)/bin/dep Gopkg.toml
	dep ensure
	mkdir -p $(OUTPUT)
	grep "$(OUTPUT)/" .gitignore 2>/dev/null || echo "$(OUTPUT)/" >>.gitignore
	go build -o "$(OUTPUT)/$(NAME)" $(LDFLAGS)

.PHONY: fmt
fmt: $(SOURCE) $(GOPATH)/bin/goimports
	go list -f '{{$$d:=.Dir}}{{range .GoFiles}}{{$$d}}/{{.}}{{"\n"}}{{end}}' ./... | xargs -L 1 goimports -l -w

$(GOPATH)/bin/goimports:
	go get golang.org/x/tools/cmd/goimports

.PHONY: test
test: $(SOURCE)
	go test ./...

.PHONY: release
release: $(SOURCE)
	docker run -i -t --rm -v `pwd`:/go/src/`go list` -w /go/src/`go list` golang:$(GOVERSION) make gox
	docker run -i -t --rm -v `pwd`:/go/src/`go list` -w /go/src/`go list` golang:$(GOVERSION) chown `id -u`:`id -g` -R build Gopkg.* vendor

.PHONY: gox
gox: $(SOURCE) $(GOPATH)/bin/gox $(GOPATH)/bin/dep Gopkg.toml
	dep ensure
	mkdir -p $(OUTPUT)/release
	grep "$(OUTPUT)/" .gitignore 2>/dev/null || echo "$(OUTPUT)/" >>.gitignore
	gox -arch "$(ARCH)" -os "$(OS)" $(LDFLAGS) -output "$(OUTPUT)/release/$(NAME)_{{.OS}}_{{.Arch}}/$(NAME)"
	cd $(OUTPUT)/release && for dir in $(foreach os,$(OS),$(foreach arch,$(ARCH),$(NAME)_$(os)_$(arch))); do \
		tar czf $${dir}.tar.gz $${dir} && rm -rf $${dir};\
	done

$(GOPATH)/bin/gox:
	go get github.com/mitchellh/gox

Gopkg.toml:
	dep init

$(GOPATH)/bin/dep:
	go get -u github.com/golang/dep/cmd/dep

.PHONY: clean
clean:
	rm -rf $(OUTPUT)

.PHONY: lint
lint: $(SOURCE) $(GOPATH)/bin/gometalinter.v2 .gometalinter.json
	gometalinter.v2 --config .gometalinter.json ./...

$(GOPATH)/bin/gometalinter.v2:
	go get -u gopkg.in/alecthomas/gometalinter.v2
	gometalinter.v2 --install

.gometalinter.json:
	echo "$${GOMETALINTER_JSON}" > .gometalinter.json

define GOMETALINTER_JSON
{
	"Enable": [
		"gotype",
		"golint",
		"varcheck",
		"structcheck",
		"maligned",
		"ineffassign",
		"interfacer",
		"unconvert",
		"goconst",
		"goimports",
		"gosimple",
		"misspell",
		"nakedret"
	],
	"Vendor": true,
	"Exclude": [
		"should have comment or be unexported",
		"should have comment \\\\(or a comment on this block\\\\) or be unexported",
		"comment on exported .* .* should be of the form",
		"don't use underscores in Go names; const",
		"a blank import should be only in a main or test package, or have a comment justifying it"
	]
}
endef

export GOMETALINTER_JSON

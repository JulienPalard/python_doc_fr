# May be overriden by calling make RELEASE=2.7
RELEASE=3.5
RELEASES=2.7 3.3 3.4 3.5

# May be overriden by calling make MODE=autobuild-stable for a full build
MODE=autobuild-html

PATCHES=$(wildcard scripts/patches/$(RELEASE)/*.patch)

PO_FILES=$(wildcard $(RELEASE)/*.po)
MO_FILES=$(addprefix gen/src/$(RELEASE)/mo/fr/LC_MESSAGES/,$(patsubst %.po,%.mo,$(notdir $(PO_FILES))))

.PHONY: $(RELEASES) $(PATCHES)

all: pull build index_page

all_releases: RULE=build
all_releases: $(RELEASES)

all_sync: RULE=sync
all_sync: $(RELEASES)

$(RELEASES):
	$(MAKE) $(RULE) RELEASE=$@ MODE=$(MODE)

gen/src/%/:
	git clone --depth 1 --branch "$(RELEASE)" https://github.com/python/cpython.git $@

requirements:
	pip -q install --user -U -r scripts/requirements.txt

pull: gen/src/$(RELEASE)/
	git -C gen/src/$(RELEASE) pull --ff-only

$(PATCHES):
	[ -f gen/src/$(RELEASE)/$(notdir $@) ] || ( \
	    cp $@ gen/src/$(RELEASE)/$(notdir $@) && \
	    git -C gen/src/$(RELEASE) apply $(notdir $@))

gen/src/%/mo/fr/LC_MESSAGES/:
	mkdir -p $@

$(MO_FILES): gen/src/$(RELEASE)/mo/fr/LC_MESSAGES/%.mo: $(RELEASE)/%.po gen/src/$(RELEASE)/mo/fr/LC_MESSAGES/
	msgfmt $< -o $@

build: gen/src/$(release)/ $(PATCHES) $(MO_FILES)
	$(MAKE) -C gen/src/$(RELEASE)/Doc/ $(MODE)

rsync: build
	# You'll need your ssh public key to be in afpy.org:/home/pythondoc/.ssh/authorized_keys
	rsync -a --delete-delay gen/src/$(RELEASE)/Doc/build/html/ pythondoc@afpy.org:/home/pythondoc/www/$(RELEASE)
	# We're reloading apache, else it misses the index.html and whines with directory listing permission denied
	ssh pythondoc@afpy.org sudo /usr/sbin/service apache2 reload

index_page:
	markdown scripts/index.md | sed '/%s/{r /dev/stdin\
	 d}' scripts/index.tpl > www/index.html

clean:
	rm -fr gen

sync:
	mkdir -p $(RELEASE)/
	cd gen/src/$(RELEASE) && sphinx-build -Q -b gettext Doc pot/
	for POT in gen/src/$(RELEASE)/pot/*; \
	do \
	    PO="$$(basename $${POT%.pot}.po)"; \
	    if [ -f "$(RELEASE)/$$PO" ]; \
	    then \
	        msgmerge -U "$(RELEASE)/$$PO" "$$POT"; \
	    else \
	        msgcat -o "$(RELEASE)/$$PO" "$$POT"; \
	    fi \
	done
	@echo "You may commit this by using git commit -u -m '$(RELEASE): merge pot files'"

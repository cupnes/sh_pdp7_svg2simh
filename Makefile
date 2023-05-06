SRC ?= test.svg
TARGET := $(SRC:.svg=.simh)
TYPE340_START_ADDR := 1000

all: $(TARGET)

%.simh: %.340simh
	cat $< type340/load_infexec_set_param_and_run.simh >$@

%.340simh: %.340ml
	tools/ml2simh $< $@ $(TYPE340_START_ADDR)

%.340ml: %.csv
	tools/ld2ml $< $@

%.csv: %.svg
	tools/svg2ld $< $@

clean:
	rm -f *~ *.340simh *.340ml *.simh common/*~ tools/*~ type340/*~

.PHONY: clean

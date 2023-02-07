.PHONY: build test docker help stage release clean latest
ifndef VERBOSE
.SILENT: build test docker help stage release clean latest
endif

SHELL=/bin/bash
VER := $(shell cat VERSION)
ORG := tacc
ALL := $(BASE) $(MPI)
IB := frontera ls6 maverick2
OPA := stampede2
SYS := $(IB) $(OPA)

BUILD = docker build --build-arg ORG=$(ORG) --build-arg VER=$(VER) --build-arg REL=$(@) -t $(ORG)/$@:$(VER) -f containers/$(@)
TAG = docker tag $(ORG)/$@:$(VER) $(ORG)/$@:latest
PUSH = docker push $(ORG)/$@:$(VER) && docker push $(ORG)/$@:latest
define TAG_AND_PUSH
	docker tag $(ORG)/$(1):$(VER) $(ORG)/$(1):latest \
	&& docker push $(ORG)/$(1):$(VER) \
	&& docker push $(ORG)/$(1):latest
endef

####################################
# CFLAGS
####################################
DEFAULT := -O2 -pipe -march=x86-64 -ftree-vectorize
# Haswell doesn't exist in all gcc versions
TACC := $(DEFAULT) -mtune=core-avx2

####################################
# Sanity checks
####################################
docker:
	docker info 1> /dev/null 2> /dev/null && \
	if [ ! $$? -eq 0 ]; then \
		echo "\n[ERROR] Could not communicate with docker daemon. You may need to run with sudo.\n"; \
		exit 1; \
	fi
containers/extras/osu-micro-benchmarks-5.4.4.tar.gz:
	cd $(dir $@) && wget http://mvapich.cse.ohio-state.edu/download/mvapich/$(notdir $@)

####################################
# Base Images
####################################
BASE := $(shell echo tacc-{ubuntu22,rockylinux8})
BASE_TEST = docker run --rm -it $(ORG)/$@:$(VER) bash -c 'echo $$CFLAGS | grep "pipe" && ls /etc/$@-release'
jammy:
	docker pull ubuntu:22.04
rockylinux8:
	docker pull rockylinux:8.7
tacc-ubuntu22: containers/tacc-ubuntu22 | docker jammy
	$(BUILD) --build-arg FLAGS="$(TACC)" ./containers &> $@.log
	$(BASE_TEST) >> $@.log 2>&1
tacc-rockylinux8: containers/tacc-rockylinux8 | docker rockylinux8
	$(BUILD) --build-arg FLAGS="$(TACC)" ./containers &> $@.log
	$(BASE_TEST) >> $@.log 2>&1
base-images: $(BASE)

clean-base: | docker
	docker rmi $(ORG)/tacc-{ubuntu22,rockylinux8}:{$(VER),latest}
push-base: | docker
	for image in $(BASE); do $(call TAG_AND_PUSH,$$image); done

####################################
# MPI Images
####################################
IMPI := $(shell echo tacc-{ubuntu22,rockylinux8}-impi19.0.9-common)
MPI := $(shell echo tacc-{ubuntu22,rockylinux8}-mvapich2.3-{ib,psm2})
MPI_TEST = docker run --rm -it $(ORG)/$@:$(VER) bash -c 'which mpicc && ls /etc/$@-release'
IMPI_TEST = $(MPI_TEST) && docker run --rm -it $(ORG)/$@:$(VER) mpirun hellow
# IB
%-mvapich2.3-ib: containers/%-mvapich2.3-ib | docker %
	$(BUILD) --build-arg FLAGS="$(TACC)" ./containers
	$(MPI_TEST)
# PSM2
%-mvapich2.3-psm2: containers/%-mvapich2.3-psm2 | docker %
	$(BUILD) --build-arg FLAGS="$(TACC)" ./containers
	$(MPI_TEST)
# IMPI
%-impi19.0.9-common: containers/%-impi19.0.9-common | docker %
	$(BUILD) --build-arg FLAGS="$(TACC)" ./containers
	$(IMPI_TEST)
mpi-images: $(MPI) $(IMPI)

clean-mpi: | docker
	docker rmi $(ORG)/tacc-{ubuntu22,rockylinux8}-mvapich2.3-{ib,psm2}:{$(VER),latest}
	docker rmi $(ORG)/tacc-{ubuntu22,rockylinux8}-impi19.0.9-common:{$(VER),latest}
push-mpi: | docker
	for image in $(MPI) $(IMPI); do $(call TAG_AND_PUSH,$$image); done
####################################
# CUDA Images
####################################


####################################
# Application Images
####################################

all: base-images mpi-images
	docker system prune

clean: clean-mpi clean-base | docker
	docker system prune

push: push-base push-mpi

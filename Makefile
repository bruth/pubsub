SRC_DIR = src
DIST_DIR = dist
TEST_DIR = test

UGLIFY = `which node` build/uglify.js --unsafe
COMPILER = `which coffee` -b -s -p
DOCCO = `which docco`

QUNIT_SM = ${SRC_DIR}/qunit

MODULES = ${SRC_DIR}/pubsub.coffee

VERSION = $(shell cat VERSION)
DATE = $(shell git log -1 --pretty=format:%ad)

all: build docs uglify

qunit:
	@@echo 'Updating QUnit...'
	@@cp ${QUNIT_SM}/qunit/qunit.* ${TEST_DIR}

compile:
	@@echo 'Compiling CoffeeScript...'
	@@mkdir -p dist
	@@cat ${MODULES} | \
		sed 's/@DATE/'"${DATE}"'/' | \
		sed 's/@VERSION/'"${VERSION}"'/' | \
		${COMPILER} > ${DIST_DIR}/pubsub.js
	@@cat ${TEST_DIR}/test.coffee | ${COMPILER} > ${TEST_DIR}/test.js

docs:
	@@echo 'Building docs...'
	@@rm -rf docs
	@@cat ${MODULES} | \
		sed 's/@DATE/'"${DATE}"'/' | \
		sed 's/@VERSION/'"${VERSION}"'/' > pubsub.coffee
		${DOCCO} pubsub.coffee
		rm pubsub.coffee

build: compile
	@@echo 'Building...'
	@@cp ${DIST_DIR}/pubsub.js ${TEST_DIR}

uglify: compile
	@@echo 'Uglifying...'
	${UGLIFY} ${DIST_DIR}/pubsub.js > ${DIST_DIR}/pubsub.min.js

pull:
	@@echo 'Pulling latest of everything...'
	@@git pull origin master
	@@if [ -d .git ]; then \
		if git submodule status | grep -q -E '^-'; then \
			git submodule update --init --recursive; \
		else \
			git submodule update --init --recursive --merge; \
		fi; \
	fi;
	@@git submodule foreach "git pull \$$(git config remote.origin.url)"	



clean:
	@@rm -rf ${DIST_DIR} \
		${TEST_DIR}/pubsub.js


.PHONY: all pull docs compile build uglify qunit clean

#!/bin/sh

cd /usr/local/lib/python3.8/site-packages && {
	find "/tmp/patches/ansible" -type f -name "*.patch" -print0 | xargs -0 -r -t -n 1 patch -p1 -i
}

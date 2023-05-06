if [ "${COMMON_COMMON_SH+is_defined}" ]; then
	return
fi
COMMON_COMMON_SH=true

die() {
	echo "$*" 1>&2
	return 1
}

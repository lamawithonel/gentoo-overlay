# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=9

inherit acct-user

DESCRIPTION="A user for sci-ml/strata"
ACCT_USER_ID=-1
ACCT_USER_HOME=/var/lib/strata
ACCT_USER_HOME_PERMS=0750
ACCT_USER_GROUPS=( strata render video )
KEYWORDS="~amd64 ~arm64"

acct-user_add_deps

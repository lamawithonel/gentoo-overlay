EAPI=5
USE_RUBY="ruby18 ruby19 ruby20 jruby rbx"

RUBY_FAKEGEM_EXTRADOC="README.md CHANGELOG.md"

RUBY_FAKEGEM_TASK_DOC=""
RUBY_FAKEGEM_RECIPE_TEST="rspec"

inherit eutils ruby-fakegem

DESCRIPTION="A Framework for Bundlers."
HOMEPAGE="https://github.com/applicationsonline/librarian"
LICENSE="MIT"

KEYWORDS="~amd64"
SLOT="0"
IUSE=""

ruby_add_bdepend "
	test? (
		dev-ruby/rake
		dev-ruby/json
		>=dev-ruby/fakefs-0.4.2
	)
"

ruby_add_rdepend "
	=dev-ruby/thor-0.15*
	dev-ruby/highline
"

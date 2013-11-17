EAPI=5
USE_RUBY="ruby18 ruby19"

RUBY_FAKEGEM_EXTRADOC="README.md"

RUBY_FAKEGEM_TASK_DOC=""
RUBY_FAKEGEM_RECIPE_TEST="cucumber"

inherit eutils ruby-fakegem

DESCRIPTION="Bundler for your Puppet modules."
HOMEPAGE="http://librarian-puppet.com"
LICENSE="MIT"

KEYWORDS="~amd64"
SLOT="0"
IUSE=""

ruby_add_bdepend "
	test? (
		dev-util/aruba
		app-admin/puppet
	)
"

ruby_add_rdepend "
	dev-ruby/librarian
	=dev-ruby/thor-0.15*
	dev-ruby/json
"

class AuthenticationBase

	attr_accessor :path
	attr_accessor :repo

	def initialize repo
		@path = "/home/git/repositories/#{repo}.git/.htpasswd"
		@repo = repo
	end

end
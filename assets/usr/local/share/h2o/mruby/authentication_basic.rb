require 'authentication_base.rb'

class AuthenticationBasic < AuthenticationBase

  def call(env)
    repo = env["PATH_INFO"]

    # remove everything until the cgi script
    repo = repo.gsub!(/^.*\/cgit\.cgi\//, "")
    # removes everything after .git as we may be looking into something like <location>/cgit.cgi/<repository>.git/tree/
    repo = repo.gsub!(/\.git.*$/, "")

    # remove anything that is not allowed
    repo.gsub!(/[^0-9A-Za-z_\-\/]/, "")

    if /DENIED/.match(`/home/git/bin/gitolite access "#{repo}" @all`)
        if File.file?("/home/git/repositories/#{repo}.git/.htpasswd")
              require "htpasswd.rb"
              Htpasswd.new(@path, @repo).call(env)
        else 
            return [403, {'content-type' => 'text/plain'}, ["access forbidden\n"]]
        end
    else
        return [399, {}, []]
    end
  end

end
require 'authentication_base.rb'
require 'lib/cookie_monster.rb'
require 'lib/uri.rb'

class AuthenticationCookie < AuthenticationBase

  def call(env)
    if /\/\.ht/.match(env['PATH_INFO'])
      return [ 404, { "Content-Type" => "text/plain" }, [ "not found" ] ]
    end

    if File.file?(@path)
      case env["REQUEST_METHOD"]
      when "POST"
        return authenticate env
      when "GET"
        return verify_authentication env
      else
        return [403, {'content-type' => 'text/plain'}, ["access forbidden\n"]]
      end

      return unauthorized
    else
      return [399, {}, []]
    end
  end

  def authenticate env
    input = env["rack.input"] ? env["rack.input"].read : ""

    # username=<user>&password=<pass>
    username, password = input.split('&', 2)
    user = URI.unescape(username.split('=', 2).last)
    pass = URI.unescape(password.split('=', 2).last)

    begin
      if lookup(user, pass)
        cookie = CookieMonster.new({:name => 'cgit.session', 
                                    :value => cookie_sign({'user' => user, 'repo' => @repo, 'path' => @path}),
                                    :path => env["PATH_INFO"].sub(/\.git.*\/$/, "\.git"),
                                    :secure => env["rack.url_scheme"] == "https" ? true : false,
                                    :httponly => true
                                    })
        
        headers = {}
        headers['Set-Cookie'] = cookie.to_s
        p headers.to_s
        p env['PATH_INFO']
        return [ 399, headers, [] ]
      end
    rescue => e
      $stderr.puts "failed to validate password using file:#{@path}:#{e.message}"
      return [ 500, { "Content-Type" => "text/plain" }, [ "Internal Server Error" ] ]
    end
  end

  def cookie_check cookie
    string = decrypt(cookie.value)
    string.gsub!(/\n$/, "")
    
    raw_hash = {}
    string.split(",").each do |v|
      raw_hash[v.split("=").first.to_sym] = v.split("=").last
    end

    if raw_hash[:repo] == @repo && raw_hash[:path] == @path
      p ":: user #{raw_hash[:user]} authorized on #{raw_hash[:repo]}"
      return [ 399, {}, [] ]
    end

    unauthorized
  end

  def cookie_sign hash_data
    string = hash_data.to_a.map{ |v| v.join("=") }.join(",")
    encrypt(string)
  end

  def encrypt string
    p "#{string}"
    `echo "#{string}" | openssl enc -aes-256-cbc -md sha512 -pbkdf2 -iter 100000 -salt -a --pass pass:lalala`
  end

  def decrypt string
    `echo "#{string}" | openssl enc -aes-256-cbc -md sha512 -pbkdf2 -iter 100000 -salt -a -d --pass pass:lalala`
  end

  def unauthorized

    html = <<HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
  <title>Repository Authentication</title>
  <link href="/css/bootstrap.min.css" rel="stylesheet">
  <link href="/css/auth.min.css" rel="stylesheet" type="text/css">
</head>
<body class="bg-blue-gradient">
  <div class="container">
    <div class="card card-login mx-auto mt-5">
      <div class="card-header">
        Repository Authentication
      </div>
      <div class="card-body">
        <form method="post">
          <div class="form-group text-center">
            <img class="login-image" src="/cgit.png" title="cgit logo" alt="cgit" />
          </div>
          <div class="form-group">
            <label for="username">Username</label>
            <input class="form-control" type="text" placeholder="this repository username" name="username" value="">
          </div>
          <div class="form-group">
            <label for="username">Password</label>
            <input class="form-control" type="password" placeholder="this repository password" name="secret">
          </div>
          <div class="form-group">
            <button class="btn btn-primary btn-block" type="submit">Send</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</body>
</html>
HTML

    return [ 401, { "Content-Type" => "text/html; charset=UTF-8" }, [html] ]
  end

  def verify_authentication env
    cookie = nil

    if ! env["HTTP_COOKIE"].nil?
      kookies = env["HTTP_COOKIE"].split(/\;\s*/)
      kookies.each do |kookie|
        kkookie = CookieMonster.new kookie

        if kkookie.name == 'cgit.session'
          return cookie_check kkookie
        end
      end
    end

    return unauthorized
  end

  def lookup(user, pass)
    File.open(@path) do |file|
      file.each_line do |line|
        line_user, hash = line.chomp.split(':', 2)
        if user == line_user && self.class.validate(pass, hash)
          return true
        end
      end
    end
    return false
  end

  class << self
    def crypt_md5(pass, salt)
      ctx = Digest::MD5.new.update("#{pass}$apr1$#{salt}")
      final = Digest::MD5.new.update("#{pass}#{salt}#{pass}").digest!.bytes

      l = pass.length
      while l > 0
        ctx.update(final[0 .. (l > 16 ? 16 : l) - 1].pack("C*"))
        l -= 16
      end

      l = pass.length
      while l > 0
        ctx.update(l % 2 != 0 ? "\0" : pass[0])
        l >>= 1
      end

      final = ctx.digest!

      1000.times do |i|
        ctx = Digest::MD5.new
        ctx.update(i % 2 != 0 ? pass : final)
        ctx.update(salt) if i % 3 != 0
        ctx.update(pass) if i % 7 != 0
        ctx.update(i % 2 != 0 ? final : pass)
        final = ctx.digest!
      end

      final = final.bytes
      hash = ""
      for a, b, c in [[0, 6, 12], [1, 7, 13], [2, 8, 14], [3, 9, 15], [4, 10, 5]]
        hash << _to64(final[a] << 16 | final[b] << 8 | final[c], 4)
      end
      hash << _to64(final[11], 2)

      "$apr1$#{salt}$#{hash}"
    end

    def _to64(v, n)
      chars = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
      output = ""
      n.times do
        output << chars[v & 0x3f]
        v >>= 6
      end
      output
    end

    def crypt_sha1(pass)
      "{SHA}" + [Digest::SHA1.new.update(pass).digest!].pack("m").chomp
    end

    def validate(pass, hash)
      if /^\$apr1\$(.*)\$/.match(hash)
        encoded = crypt_md5(pass, $1)
      elsif /^{SHA}/.match(hash)
        encoded = crypt_sha1(pass)
      else
        raise "crypt-style password hash is not supported"
      end
      return encoded == hash
    end
  end
end
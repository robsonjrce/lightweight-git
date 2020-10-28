class Htlocked

  attr_accessor :path
  attr_accessor :repo

  def initialize repo
    @path = "/home/git/repositories/#{repo}.git/.htlocked"
    @repo = repo
  end

  def isLocked?
    File.file?(@path)
  end

  def lock
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
<body class="bg-red-gradient">
  <div class="container">
    <div class="card card-login mx-auto mt-5">
      <div class="card-header">
        Repository Locked !
      </div>
      <div class="card-body">
        <form method="post">
          <div class="form-group text-center">
            <img class="login-image" src="/locked_icon_red.svg" width="200px" title="Locked Icon" alt="cgit" />
          </div>
          <!-- Image source: https://commons.wikimedia.org/wiki/File:Locked_icon_red.svg -->
        </div>
      </div>
    </div>
  </div>
</body>
</html>
HTML

    return [ 403, { "Content-Type" => "text/html; charset=UTF-8" }, [html] ]    
  end
end
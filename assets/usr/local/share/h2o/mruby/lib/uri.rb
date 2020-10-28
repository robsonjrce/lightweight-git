# @see https://github.com/iij/mruby-webapi/blob/master/mrblib/webapi.rb

class URI
  CRLF = "\r\n"
  FORMCHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~"

  MAXHEADERBYTES = 65536
  MAXHEADERCOUNT = 64

  class << self

    def unescape(s)
      HEXA = "0123456789ABCDEFabcdef"
      i = 0
      t = ""
      while i < s.size
        if s[i] == "%"
          if i + 2 < s.size and HEXA.include?(s[i+1]) and HEXA.include?(s[i+2])
            t += s[i+1..i+2].to_i(16).chr
            i += 2
          else
            raise "invalid percent sequence in URL encoded string"
          end
        elsif s[i] == "+"
          t += " "
        else
          t += s[i]
        end
        i += 1
      end
      t
    end

    def escape(s)
      t = ""
      s.each_char { |ch|
        if FORMCHARS.include?(ch)
          t += ch
        elsif ch == " "
          t += "+"
        else
          t += format("%%%02X", ch.getbyte(0))
        end
      }
      t
    end

  end
end
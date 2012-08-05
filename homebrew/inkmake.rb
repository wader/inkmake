require 'formula'

class Inkmake < Formula
  head 'https://github.com/wader/inkmake.git', :branch => 'master'
  homepage 'https://github.com/wader/inkmake'

  def install
    bin.install "inkmake"
  end
end

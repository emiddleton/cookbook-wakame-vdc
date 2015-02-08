require 'serverspec'

# Required by serverspec
set :backend, :exec

describe "Wakame VDC" do

  describe bridge('br0') do
    it { should exist }
  end

  it "is listening on port 9000" do
    expect(port(9000)).to be_listening
  end

  it "is listening on port 9001" do
    expect(port(9001)).to be_listening
  end

end

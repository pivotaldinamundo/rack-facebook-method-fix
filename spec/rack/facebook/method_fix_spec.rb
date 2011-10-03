require File.expand_path('spec_helper', File.join(File.dirname(__FILE__), '../../'))
require 'base64'
require 'openssl'

class MockRackWrapper
  def initialize(response)
    @response = response
  end

  def call(env)
    @env = env
    @response
  end

  def env
    @env
  end
end

describe Rack::Facebook::MethodFix do
  let(:header) { [200, {"Content-type" => "test/plain", "Content-length" => "5"}, ["foo"]] }
  let(:mock_rack_app) { MockRackWrapper.new(header) }

  context "with no exclusions" do
    before do
      facebook_method_fix_app = Rack::Facebook::MethodFix.new(mock_rack_app)
      @request = Rack::MockRequest.new(facebook_method_fix_app)
    end

    context "POST requests not from facebook" do
      it 'should stay as a POST' do
        @request.post("/", {})
        mock_rack_app.env["REQUEST_METHOD"].should == "POST"
      end
    end

    context 'POST requests from facebook' do
      context "when given an app secret" do
        let(:secret) { "3d94b435641d85bd3ec5da171cdabaf0" }
        let(:valid_signed_request) { "QCd8WudFOVM8xp05tKs9AwNYCkbF2io8Hn7PoiTdK7k.eyJhbGdvcml0aG0iOiJITUFDLVNIQTI1NiIsImlzc3VlZF9hdCI6MTMxNzQwMzc0OCwidXNlciI6eyJjb3VudHJ5IjoidXMiLCJsb2NhbGUiOiJlbl9VUyIsImFnZSI6eyJtaW4iOjAsIm1heCI6MTJ9fX0" }
        let(:payload) {
          {"algorithm"=>"HMAC-SHA256", "issued_at"=>1317403748, "user"=>{"country"=>"us", "locale"=>"en_US", "age"=>{"min"=>0, "max"=>12}}}
        }
        before do
          facebook_method_fix_app = Rack::Facebook::MethodFix.new(mock_rack_app, :secret_id => secret)
          @request = Rack::MockRequest.new(facebook_method_fix_app)
        end
        context "with a valid signature in the signed request" do
          before do
            params = {:params => {"signed_request" => valid_signed_request}}
            @request.post('/foo', params)
          end
          it "makes the parsed signed request hash available in env" do
            mock_rack_app.env["facebook.signed_request"].should == payload
          end

          it "is changed to a GET request" do
            mock_rack_app.env["REQUEST_METHOD"].should == "GET"
          end
        end
        context "with an invalid signature in the signed request (and therefore, did not come from FB)" do
          it "does not change it to a GET request" do
            invalid_signed_request = '1234567.eyJhbGdvcml0aG0iOiJITUFDLVNIQTI1NiIsImlzc3VlZF9hdCI6MTMxNzQwMzc0OCwidXNlciI6eyJjb3VudHJ5IjoidXMiLCJsb2NhbGUiOiJlbl9VUyIsImFnZSI6eyJtaW4iOjAsIm1heCI6MTJ9fX0'
            @request.post("/", {:params => {"signed_request" => invalid_signed_request}})
            mock_rack_app.env["REQUEST_METHOD"].should == "POST"
          end
        end
      end

      context "when not given an app secret" do
        describe "signed request parsing" do
          it "changes the post to a get and makes the parsed signed request hash available in env even if the signature is invalid" do
            facebook_method_fix_app = Rack::Facebook::MethodFix.new(mock_rack_app)
            @request = Rack::MockRequest.new(facebook_method_fix_app)
            json_hash = {"algorithm"=>"HMAC-SHA256", "issued_at"=>1317403748, "user"=>{"country"=>"us", "locale"=>"en_US", "age"=>{"min"=>0, "max"=>12}}}
            signed_request = "FakeSignature123.eyJhbGdvcml0aG0iOiJITUFDLVNIQTI1NiIsImlzc3VlZF9hdCI6MTMxNzQwMzc0OCwidXNlciI6eyJjb3VudHJ5IjoidXMiLCJsb2NhbGUiOiJlbl9VUyIsImFnZSI6eyJtaW4iOjAsIm1heCI6MTJ9fX0"
            params = {:params => {"signed_request" => signed_request}}
            @request.post('/foo', params)
            mock_rack_app.env["facebook.signed_request"].should == json_hash
            mock_rack_app.env["REQUEST_METHOD"].should == "GET"
          end
        end
      end
    end
  end

  context 'when the middleware is passed an exclusion proc' do
    before do
      exclusion_proc = proc { |env| env['PATH_INFO'].match(/^\/admin/) }
      facebook_method_fix_app = Rack::Facebook::MethodFix.new(mock_rack_app, :exclude => exclusion_proc)
      @request = Rack::MockRequest.new(facebook_method_fix_app)
    end

    it "does not change requests that are not from facebook" do
      @request.post('/', {})
      mock_rack_app.env["REQUEST_METHOD"].should == "POST"
    end

    context "requests from facebook " do
      let(:params) { {:params => {"signed_request" => 'nothing'}} }
      it "changes POSTs to GETs the exclusion proc returns false" do
        @request.post('/foo', params)
        mock_rack_app.env["REQUEST_METHOD"].should == "GET"
      end

      it "does not change POSTs when the exclusion proc returns true" do
        @request.post('/admin/foo', params)
        mock_rack_app.env["REQUEST_METHOD"].should == "POST"
      end
    end
  end

end

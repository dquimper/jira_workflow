require 'test/unit'
require 'mocha/test_unit'
require 'net/http'
require 'json'
require 'base64'

# Load the JiraHelper class from the script
load File.expand_path('../bin/jw', __dir__)

class JiraHelperTest < Test::Unit::TestCase
  def setup
    @jira_key = 'TEST-123'
    @expected_summary = 'Test Jira Issue'
    @api_key = 'test_api_key'
    @original_api_key = ENV['JIRA_WORKFLOW_API_KEY']
    ENV['JIRA_WORKFLOW_API_KEY'] = @api_key
  end

  def teardown
    ENV['JIRA_WORKFLOW_API_KEY'] = @original_api_key
  end

  def test_get_summary_success
    # Mock the HTTP response
    mock_response = mock_http_response(200, {
      'fields' => {
        'summary' => @expected_summary
      }
    }.to_json)

    Net::HTTP.expects(:start).returns(mock_response)

    issue = JiraHelper.get_issue(@jira_key)
    assert_equal @expected_summary, JiraHelper.get_summary(issue)
  end

  def test_get_summary_http_error
    # Mock the HTTP response with an error
    mock_response = mock_http_response(404, 'Not Found')

    Net::HTTP.expects(:start).returns(mock_response)

    assert_raises(JwError) do
      issue = JiraHelper.get_issue(@jira_key)
      JiraHelper.get_summary(issue)
    end
  end

  def test_get_summary_json_parse_error
    # Mock the HTTP response with invalid JSON
    mock_response = mock_http_response(200, 'invalid json')

    Net::HTTP.expects(:start).returns(mock_response)
    assert_raises(JwError) do
      issue = JiraHelper.get_issue(@jira_key)
      JiraHelper.get_summary(issue)
    end
  end

  private

  def mock_http_response(status_code, body)
    response = Net::HTTPResponse.new('1.1', status_code, 'OK')
    def response.body
      @body
    end
    def response.body=(value)
      @body = value
    end
    def response.is_a?(klass)
      klass == Net::HTTPSuccess
    end
    response.body = body
    response
  end
end 
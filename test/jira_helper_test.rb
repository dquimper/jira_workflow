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

  def test_get_status_success
    # Mock the HTTP response
    mock_response = mock_http_response(200, {
      'fields' => {
        'status' => {
          'name' => 'In Progress'
        }
      }
    }.to_json)

    Net::HTTP.expects(:start).returns(mock_response)

    issue = JiraHelper.get_issue(@jira_key)
    assert_equal 'In Progress', JiraHelper.get_status(issue)
  end

  def test_transition_map_success
    # Mock the HTTP response with transitions
    transitions_data = {
      'transitions' => [
        { 'name' => 'In Progress', 'id' => '11' },
        { 'name' => 'Done', 'id' => '21' }
      ]
    }
    mock_response = mock_http_response(200, transitions_data.to_json)

    Net::HTTP.expects(:start).returns(mock_response)

    result = JiraHelper.transition_map(@jira_key)
    assert_equal({ 'In Progress' => '11', 'Done' => '21' }, result)
  end

  def test_transition_map_http_error
    # Mock the HTTP response with an error
    mock_response = mock_http_response(404, 'Not Found')

    Net::HTTP.expects(:start).returns(mock_response)

    assert_raises(JwError) do
      JiraHelper.transition_map(@jira_key)
    end
  end

  def test_set_status_success
    # Stub transition_map to return a valid transition map
    JiraHelper.expects(:transition_map).with(@jira_key).returns({ 'In Progress' => '11' })

    # Mock the POST request for set_status (204 No Content is success)
    set_status_response = mock_http_response(204, '')

    # Net::HTTP.start yields an http object, and http.request returns the response
    mock_http = mock
    mock_http.expects(:request).returns(set_status_response)
    Net::HTTP.expects(:start).yields(mock_http).returns(set_status_response)

    # Should not raise an error
    assert_nothing_raised do
      JiraHelper.set_status(@jira_key, 'In Progress')
    end
  end

  def test_set_status_http_error
    # Stub transition_map to return a valid transition map
    JiraHelper.expects(:transition_map).with(@jira_key).returns({ 'In Progress' => '11' })

    # Mock the POST request with an error (400 Bad Request)
    set_status_response = mock_http_response(400, 'Bad Request')
    # Verify the mock response returns false for HTTPSuccess check
    assert_equal false, set_status_response.is_a?(Net::HTTPSuccess), "Mock response should not be HTTPSuccess"

    # Net::HTTP.start yields an http object, and http.request returns the response
    # The block's return value becomes the return value of start
    mock_http = mock
    mock_http.expects(:request).returns(set_status_response)
    Net::HTTP.expects(:start).yields(mock_http).returns(set_status_response)

    error = assert_raises(JwError) do
      JiraHelper.set_status(@jira_key, 'In Progress')
    end
    assert_match(/Error updating Jira issue status/, error.message)
  end

  def test_get_issue_standard_error
    # Mock Net::HTTP.start to raise a standard error
    Net::HTTP.expects(:start).raises(StandardError.new('Connection error'))

    assert_raises(JwError) do
      JiraHelper.get_issue(@jira_key)
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
      # Net::HTTPSuccess is a module included in success response classes
      # For status codes 200-299, return true, otherwise false
      if klass == Net::HTTPSuccess
        @status_code >= 200 && @status_code < 300
      else
        super
      end
    end
    def response.code
      @status_code.to_s
    end
    def response.message
      @message || 'OK'
    end
    response.instance_variable_set(:@status_code, status_code)
    response.body = body
    response
  end
end 
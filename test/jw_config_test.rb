require 'test/unit'
require 'tempfile'

# Load the JwConfig class from the script
load File.expand_path('../bin/jw', __dir__)

class JwConfigTest < Test::Unit::TestCase
  def setup
    @config = JwRcConfig.new({})
    @jw_config = JwConfig.new(@config)
  end

  def teardown
    # Clean up
    system("git config --local --unset jw.test-key")
  end

  def test_get_config_value
    # Set a test value using git config
    system("git config set --local jw.test-key 'test_value'")
    
    # Test getting the value
    assert_equal 'test_value', @jw_config.get('test-key')
  end

  def test_get_nonexistent_config_value
    # Test getting a value that doesn't exist
    assert_nil @jw_config.get('nonexistent-key')
  end

  def test_set_config_value
    # Set a value using the set method
    assert @jw_config.set('test-key', 'test-value')
    
    # Verify the value was set
    assert_equal 'test-value', @jw_config.get('test-key')
  end
end 
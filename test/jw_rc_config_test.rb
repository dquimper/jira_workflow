require 'test/unit'
require 'yaml'
require 'tempfile'

# Load the JwRcConfig class from the script
load File.expand_path('../bin/jw', __dir__)

class JwRcConfigTest < Test::Unit::TestCase
  def setup
    @config = {
      'test_key' => 'test_value',
      :symbol_key => 'symbol_value',
      'config_scope' => 'global'
    }
    @jw_rc_config = JwRcConfig.new(@config)
  end

  def test_initialize_with_config
    assert_equal 'test_value', @jw_rc_config['test_key']
    assert_equal 'symbol_value', @jw_rc_config[:symbol_key]
  end

  def test_access_with_string_or_symbol
    assert_equal 'test_value', @jw_rc_config['test_key']
    assert_equal 'test_value', @jw_rc_config[:test_key]
  end

  def test_config_scope
    assert_equal 'global', @jw_rc_config.config_scope
  end

  def test_config_scope_default
    config = JwRcConfig.new({})
    assert_equal 'local', config.config_scope
  end

  def test_method_missing
    assert_equal 'test_value', @jw_rc_config.test_key
  end

  def test_load_from_file
    temp_file = Tempfile.new('config')
    begin
      YAML.dump({ 'test_key' => 'file_value' }, temp_file)
      temp_file.close

      config = JwRcConfig.load(temp_file.path)
      assert_equal 'file_value', config['test_key']
    ensure
      temp_file.unlink
    end
  end

  def test_load_from_nonexistent_file
    config = JwRcConfig.load('/nonexistent/path/to/config.yml')
    assert_equal({}, config.instance_variable_get(:@config))
  end
end

require 'test/unit'
require 'mocha/test_unit'
require 'tempfile'

# Load the JiraWorkflow class from the script
load File.expand_path('../bin/jw', __dir__)

class JiraWorkflowTest < Test::Unit::TestCase
  def setup
    @rc = JwRcConfig.new({})
    @jw_config = JwConfig.new(@rc)
    @git_helper = GitHelper.new(@rc, @jw_config)
    @jira_key = 'TEST-123'
    @commit_sha = 'abc123def456'
    @short_sha = 'abc123de'  # sha[0..7] gives 8 characters (indices 0-7)
  end

  def test_update_commit_sha_option_parsing
    # Test that -s option is parsed correctly
    jw = JiraWorkflow.new(['-s', @commit_sha])
    assert_equal @commit_sha, jw.instance_variable_get(:@options)[:update_commit_sha]
  end

  def test_update_commit_sha_option_parsing_long_form
    # Test that --update-commit-sha option is parsed correctly
    jw = JiraWorkflow.new(['--update-commit-sha', @commit_sha])
    assert_equal @commit_sha, jw.instance_variable_get(:@options)[:update_commit_sha]
  end

  def test_update_commit_sha_with_nonexistent_commit
    # Test that update_commit_sha raises error for nonexistent commit
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Mock git rev-parse to return false (commit doesn't exist)
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(false)
    
    assert_raises(JwError) do
      jw.update_commit_sha(@commit_sha)
    end
  end

  def test_update_commit_sha_with_empty_commit_message
    # Test that update_commit_sha raises error for empty commit message
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Mock git rev-parse to return true (commit exists)
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to return empty message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns('')
    
    assert_raises(JwError) do
      jw.update_commit_sha(@commit_sha)
    end
  end

  def test_update_commit_sha_for_head_commit
    # Test updating commit message for HEAD commit (uses amend)
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Set up JIRA key in config
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    
    original_msg = 'Original commit message'
    expected_msg = "[#{@jira_key}] #{original_msg}"
    escaped_msg = expected_msg.gsub(/'/, "'\\''")
    
    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns(original_msg)
    
    # Mock git rev-parse HEAD to return the same SHA
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(@commit_sha)
    
    # Mock git commit --amend
    JiraWorkflow.any_instance.expects(:system).with("git commit --amend -m '#{escaped_msg}'").returns(true)
    
    # Mock puts
    JiraWorkflow.any_instance.expects(:puts).with("Commit message updated for HEAD")
    
    jw.update_commit_sha(@commit_sha)
  end

  def test_update_commit_sha_for_head_commit_with_existing_jira_key
    # Test updating commit message for HEAD when commit already has JIRA key — message left unchanged
    jw = JiraWorkflow.new(['-s', @commit_sha])

    # Set up JIRA key in config
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)

    original_msg = "[OLD-456] Original commit message"
    escaped_msg = original_msg.gsub(/'/, "'\\''")

    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)

    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns(original_msg)

    # Mock git rev-parse HEAD to return the same SHA
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(@commit_sha)

    # Mock git commit --amend with the original (unchanged) message
    JiraWorkflow.any_instance.expects(:system).with("git commit --amend -m '#{escaped_msg}'").returns(true)

    # Mock puts
    JiraWorkflow.any_instance.expects(:puts).with("Commit message updated for HEAD")

    jw.update_commit_sha(@commit_sha)
  end

  def test_update_commit_sha_for_non_head_commit
    # Test updating commit message for non-HEAD commit (uses rebase)
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Set up JIRA key in config
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    
    original_msg = 'Original commit message'
    expected_msg = "[#{@jira_key}] #{original_msg}"
    parent_sha = 'parent123'
    current_head = 'head789'
    
    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns(original_msg)
    
    # Mock git rev-parse HEAD to return different SHA
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(current_head)
    
    # Mock git rev-parse to get parent
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse '#{@commit_sha}^' 2>/dev/null").returns(parent_sha)
    
    # Mock File.write for temp scripts
    File.expects(:write).at_least_once
    File.expects(:chmod).at_least_once
    
    # Mock git rebase -i
    JiraWorkflow.any_instance.expects(:system).with(anything, "git rebase -i '#{parent_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git rev-parse to check for REBASE_HEAD
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify REBASE_HEAD > /dev/null 2>&1").returns(false)
    
    # Mock File.exist? and File.delete for cleanup
    File.expects(:exist?).at_least_once.returns(true)
    File.expects(:delete).at_least_once
    
    # Mock puts
    JiraWorkflow.any_instance.expects(:puts).with("Commit message updated for SHA #{@short_sha}")
    
    jw.update_commit_sha(@commit_sha)
  end

  def test_update_commit_sha_for_root_commit
    # Test that update_commit_sha raises error for root commit (no parent)
    jw = JiraWorkflow.new(['-s', @commit_sha])
    current_head = 'head789'
    
    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns('Some message')
    
    # Mock git rev-parse HEAD to return different SHA
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(current_head)
    
    # Mock git rev-parse to get parent (returns empty - root commit)
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse '#{@commit_sha}^' 2>/dev/null").returns('')
    
    assert_raises(JwError) do
      jw.update_commit_sha(@commit_sha)
    end
  end

  def test_update_commit_sha_without_jira_key
    # Test that update_commit_sha returns original message if no JIRA key is set
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Don't set JIRA key in config
    
    original_msg = 'Original commit message'
    current_head = 'head789'
    
    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns(original_msg)
    
    # Mock git rev-parse HEAD to return different SHA
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(current_head)
    
    # Mock git rev-parse to get parent
    parent_sha = 'parent123'
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse '#{@commit_sha}^' 2>/dev/null").returns(parent_sha)
    
    # Mock File.write for temp scripts
    File.expects(:write).at_least_once
    File.expects(:chmod).at_least_once
    
    # Mock git rebase -i (should use original message since no JIRA key)
    JiraWorkflow.any_instance.expects(:system).with(anything, "git rebase -i '#{parent_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git rev-parse to check for REBASE_HEAD
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify REBASE_HEAD > /dev/null 2>&1").returns(false)
    
    # Mock File.exist? and File.delete for cleanup
    File.expects(:exist?).at_least_once.returns(true)
    File.expects(:delete).at_least_once
    
    # Mock puts
    JiraWorkflow.any_instance.expects(:puts).with("Commit message updated for SHA #{@short_sha}")
    
    jw.update_commit_sha(@commit_sha)
  end

  def test_update_commit_sha_amend_failure
    # Test that update_commit_sha raises error when amend fails
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Set up JIRA key in config
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    
    original_msg = 'Original commit message'
    expected_msg = "[#{@jira_key}] #{original_msg}"
    escaped_msg = expected_msg.gsub(/'/, "'\\''")
    
    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns(original_msg)
    
    # Mock git rev-parse HEAD to return the same SHA
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(@commit_sha)
    
    # Mock git commit --amend to return false (failure)
    JiraWorkflow.any_instance.expects(:system).with("git commit --amend -m '#{escaped_msg}'").returns(false)
    
    assert_raises(JwError) do
      jw.update_commit_sha(@commit_sha)
    end
  end

  def test_update_commit_sha_rebase_failure
    # Test that update_commit_sha raises error when rebase fails
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Set up JIRA key in config
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    
    original_msg = 'Original commit message'
    current_head = 'head789'
    parent_sha = 'parent123'
    
    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns(original_msg)
    
    # Mock git rev-parse HEAD to return different SHA
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(current_head)
    
    # Mock git rev-parse to get parent
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse '#{@commit_sha}^' 2>/dev/null").returns(parent_sha)
    
    # Mock File.write for temp scripts
    File.expects(:write).at_least_once
    File.expects(:chmod).at_least_once
    
    # Mock git rebase -i to return false (failure)
    JiraWorkflow.any_instance.expects(:system).with(anything, "git rebase -i '#{parent_sha}' > /dev/null 2>&1").returns(false)
    
    # Mock File.exist? and File.delete for cleanup (called even on failure)
    File.expects(:exist?).at_least_once.returns(true)
    File.expects(:delete).at_least_once
    
    assert_raises(JwError) do
      jw.update_commit_sha(@commit_sha)
    end
  end

  def test_run_with_update_commit_sha_option
    # Test that run method calls update_commit_sha when -s option is provided
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Mock update_commit_sha to be called
    jw.expects(:update_commit_sha).with(@commit_sha).returns(nil)
    
    jw.run
  end

  def test_init_option_parsing
    # Test that -i option is parsed correctly
    jw = JiraWorkflow.new(['-i', 'develop'])
    assert_equal 'develop', jw.instance_variable_get(:@options)[:init]
  end

  def test_init_option_parsing_long_form
    # Test that --init option is parsed correctly
    jw = JiraWorkflow.new(['--init', 'main'])
    assert_equal 'main', jw.instance_variable_get(:@options)[:init]
  end

  def test_reset_option_parsing
    # Test that -r option is parsed correctly
    jw = JiraWorkflow.new(['-r'])
    assert_equal true, jw.instance_variable_get(:@options)[:reset]
  end

  def test_reset_option_parsing_long_form
    # Test that --reset option is parsed correctly
    jw = JiraWorkflow.new(['--reset'])
    assert_equal true, jw.instance_variable_get(:@options)[:reset]
  end

  def test_commit_msg_hook_option_parsing
    # Test that --commit-msg-hook option is parsed correctly
    jw = JiraWorkflow.new(['--commit-msg-hook'])
    assert_equal true, jw.instance_variable_get(:@options)[:commit_msg]
  end

  def test_set_init
    # Test set_init method
    jw = JiraWorkflow.new([])
    
    # Mock jw_config.set
    jw.instance_variable_get(:@jw_config).expects(:set).with('default-branch', 'develop')
    
    jw.set_init('develop')
  end

  def test_reset_config
    # Test reset_config method
    jw = JiraWorkflow.new([])
    
    # Mock jw_config.set for each key
    jw.instance_variable_get(:@jw_config).expects(:set).with('key', '')
    jw.instance_variable_get(:@jw_config).expects(:set).with('summary', '')
    jw.instance_variable_get(:@jw_config).expects(:set).with('default-branch', '')
    
    # Mock puts
    JiraWorkflow.any_instance.expects(:puts).with('Jira Workflow configs reset')
    
    jw.reset_config
  end

  def test_display_jira_workflow_configs_with_config
    # Test display_jira_workflow_configs when config exists
    jw = JiraWorkflow.new([])
    
    # Set up config values
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    jw.instance_variable_get(:@jw_config).set('summary', 'Test Summary')
    
    # Mock get calls
    jw.instance_variable_get(:@jw_config).expects(:get).with('key').returns(@jira_key)
    jw.instance_variable_get(:@jw_config).expects(:get).with('summary').returns('Test Summary')
    
    # Mock default_branch
    jw.instance_variable_get(:@git_helper).expects(:default_branch).returns('main')
    
    # Mock puts calls
    JiraWorkflow.any_instance.expects(:puts).with("Jira key:       #{@jira_key}")
    JiraWorkflow.any_instance.expects(:puts).with("Jira summary:   Test Summary")
    JiraWorkflow.any_instance.expects(:puts).with("Default branch: main")
    
    jw.display_jira_workflow_configs
  end

  def test_display_jira_workflow_configs_without_config
    # Test display_jira_workflow_configs when config doesn't exist
    jw = JiraWorkflow.new([])
    
    # Mock get calls to return nil (method checks both key and summary)
    jw.instance_variable_get(:@jw_config).expects(:get).with('key').returns(nil)
    jw.instance_variable_get(:@jw_config).expects(:get).with('summary').returns(nil)
    
    # Mock puts
    JiraWorkflow.any_instance.expects(:puts).with('No Jira Workflow configs found')
    
    jw.display_jira_workflow_configs
  end

  def test_update_commit_msg_with_jira_key
    # Test update_commit_msg when JIRA key is set
    jw = JiraWorkflow.new([])
    
    # Set up JIRA key
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    jw.instance_variable_get(:@jw_config).expects(:get).with('key').returns(@jira_key)
    
    original_msg = 'Original commit message'
    expected_msg = "[#{@jira_key}] #{original_msg}"
    
    result = jw.update_commit_msg(original_msg)
    assert_equal expected_msg, result
  end

  def test_update_commit_msg_without_jira_key
    # Test update_commit_msg when JIRA key is not set
    jw = JiraWorkflow.new([])
    
    # Mock get to return nil
    jw.instance_variable_get(:@jw_config).expects(:get).with('key').returns(nil)
    
    original_msg = 'Original commit message'
    
    result = jw.update_commit_msg(original_msg)
    assert_equal original_msg, result
  end

  def test_update_commit_msg_preserves_existing_jira_key
    # Test update_commit_msg leaves message unchanged when it already has a JIRA key
    jw = JiraWorkflow.new([])

    # Set up JIRA key
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    jw.instance_variable_get(:@jw_config).expects(:get).with('key').returns(@jira_key)

    original_msg = "[OLD-456] Original commit message"

    result = jw.update_commit_msg(original_msg)
    assert_equal original_msg, result
  end

  def test_set_commit_msg_success
    # Test set_commit_msg with valid file
    jw = JiraWorkflow.new(['--commit-msg-hook'])
    
    # Create a temporary file
    temp_file = Tempfile.new('commit_msg')
    temp_file.write('Original commit message')
    temp_file.close
    
    begin
      # Set up JIRA key
      jw.instance_variable_get(:@jw_config).set('key', @jira_key)
      jw.instance_variable_get(:@jw_config).expects(:get).with('key').returns(@jira_key)
      
      # Mock puts — should output the key that ends up in the commit
      JiraWorkflow.any_instance.expects(:puts).with(@jira_key)

      jw.set_commit_msg([temp_file.path])
      
      # Verify file was updated
      updated_content = File.read(temp_file.path)
      assert_equal "[#{@jira_key}] Original commit message", updated_content
    ensure
      temp_file.unlink
    end
  end

  def test_set_commit_msg_outputs_existing_key_when_already_present
    jw = JiraWorkflow.new(['--commit-msg-hook'])

    temp_file = Tempfile.new('commit_msg')
    temp_file.write('[OLD-456] Already keyed message')
    temp_file.close

    begin
      jw.instance_variable_get(:@jw_config).set('key', @jira_key)
      jw.instance_variable_get(:@jw_config).expects(:get).with('key').returns(@jira_key)

      JiraWorkflow.any_instance.expects(:puts).with('OLD-456')

      jw.set_commit_msg([temp_file.path])

      assert_equal '[OLD-456] Already keyed message', File.read(temp_file.path)
    ensure
      temp_file.unlink
    end
  end

  def test_set_commit_msg_no_file_provided
    # Test set_commit_msg raises error when no file is provided
    jw = JiraWorkflow.new(['--commit-msg-hook'])
    
    assert_raises(JwError) do
      jw.set_commit_msg([])
    end
  end

  def test_set_commit_msg_file_does_not_exist
    # Test set_commit_msg raises error when file doesn't exist
    jw = JiraWorkflow.new(['--commit-msg-hook'])
    
    assert_raises(JwError) do
      jw.set_commit_msg(['/nonexistent/file'])
    end
  end

  def test_set_commit_msg_empty_file
    # Test set_commit_msg raises error when file is empty
    jw = JiraWorkflow.new(['--commit-msg-hook'])
    
    temp_file = Tempfile.new('commit_msg')
    temp_file.close
    
    begin
      assert_raises(JwError) do
        jw.set_commit_msg([temp_file.path])
      end
    ensure
      temp_file.unlink
    end
  end

  def test_set_jira_workflow_configs_success
    # Test set_jira_workflow_configs with valid JIRA key
    jw = JiraWorkflow.new(['TEST-123'])
    
    # Mock JiraHelper methods
    mock_issue = {
      'fields' => {
        'summary' => 'Test Summary',
        'status' => { 'name' => 'To Do' }
      }
    }
    JiraHelper.expects(:get_issue).with('TEST-123').returns(mock_issue)
    JiraHelper.expects(:get_summary).with(mock_issue).returns('Test Summary')
    JiraHelper.expects(:get_status).with(mock_issue).returns('To Do')
    JiraHelper.expects(:set_status).with('TEST-123', 'In Progress')
    
    # Mock jw_config.set
    jw.instance_variable_get(:@jw_config).expects(:set).with('key', 'TEST-123')
    jw.instance_variable_get(:@jw_config).expects(:set).with('summary', 'Test Summary')
    
    # Mock display_jira_workflow_configs
    jw.expects(:display_jira_workflow_configs)
    
    # Mock git_helper.create_branch
    jw.instance_variable_get(:@git_helper).expects(:create_branch).with('test-123')
    
    jw.set_jira_workflow_configs('TEST-123')
  end

  def test_set_jira_workflow_configs_already_in_progress
    # Test set_jira_workflow_configs when status is already "In Progress"
    jw = JiraWorkflow.new(['TEST-123'])
    
    # Mock JiraHelper methods
    mock_issue = {
      'fields' => {
        'summary' => 'Test Summary',
        'status' => { 'name' => 'In Progress' }
      }
    }
    JiraHelper.expects(:get_issue).with('TEST-123').returns(mock_issue)
    JiraHelper.expects(:get_summary).with(mock_issue).returns('Test Summary')
    JiraHelper.expects(:get_status).with(mock_issue).returns('In Progress')
    # Should NOT call set_status when already "In Progress"
    JiraHelper.expects(:set_status).never
    
    # Mock jw_config.set
    jw.instance_variable_get(:@jw_config).expects(:set).with('key', 'TEST-123')
    jw.instance_variable_get(:@jw_config).expects(:set).with('summary', 'Test Summary')
    
    # Mock display_jira_workflow_configs
    jw.expects(:display_jira_workflow_configs)
    
    # Mock git_helper.create_branch
    jw.instance_variable_get(:@git_helper).expects(:create_branch).with('test-123')
    
    jw.set_jira_workflow_configs('TEST-123')
  end

  def test_set_jira_workflow_configs_invalid_key
    # Test set_jira_workflow_configs with invalid JIRA key format
    jw = JiraWorkflow.new(['invalid'])
    
    assert_raises(JwError) do
      jw.set_jira_workflow_configs('invalid')
    end
  end

  def test_set_jira_workflow_configs_with_slash_prefix
    # Test set_jira_workflow_configs with JIRA key that has slash prefix
    jw = JiraWorkflow.new(['/TEST-123'])
    
    # Mock JiraHelper methods
    mock_issue = {
      'fields' => {
        'summary' => 'Test Summary',
        'status' => { 'name' => 'To Do' }
      }
    }
    JiraHelper.expects(:get_issue).with('TEST-123').returns(mock_issue)
    JiraHelper.expects(:get_summary).with(mock_issue).returns('Test Summary')
    JiraHelper.expects(:get_status).with(mock_issue).returns('To Do')
    JiraHelper.expects(:set_status).with('TEST-123', 'In Progress')
    
    # Mock jw_config.set
    jw.instance_variable_get(:@jw_config).expects(:set).with('key', 'TEST-123')
    jw.instance_variable_get(:@jw_config).expects(:set).with('summary', 'Test Summary')
    
    # Mock display_jira_workflow_configs
    jw.expects(:display_jira_workflow_configs)
    
    # Mock git_helper.create_branch
    jw.instance_variable_get(:@git_helper).expects(:create_branch).with('test-123')
    
    jw.set_jira_workflow_configs('/TEST-123')
  end

  def test_set_jira_workflow_configs_lowercase_key
    # Test set_jira_workflow_configs with lowercase JIRA key (should be upcased)
    jw = JiraWorkflow.new(['test-123'])
    
    # Mock JiraHelper methods
    mock_issue = {
      'fields' => {
        'summary' => 'Test Summary',
        'status' => { 'name' => 'To Do' }
      }
    }
    JiraHelper.expects(:get_issue).with('TEST-123').returns(mock_issue)
    JiraHelper.expects(:get_summary).with(mock_issue).returns('Test Summary')
    JiraHelper.expects(:get_status).with(mock_issue).returns('To Do')
    JiraHelper.expects(:set_status).with('TEST-123', 'In Progress')
    
    # Mock jw_config.set
    jw.instance_variable_get(:@jw_config).expects(:set).with('key', 'TEST-123')
    jw.instance_variable_get(:@jw_config).expects(:set).with('summary', 'Test Summary')
    
    # Mock display_jira_workflow_configs
    jw.expects(:display_jira_workflow_configs)
    
    # Mock git_helper.create_branch
    jw.instance_variable_get(:@git_helper).expects(:create_branch).with('test-123')
    
    jw.set_jira_workflow_configs('test-123')
  end

  def test_run_with_init_option
    # Test run method with -i option
    jw = JiraWorkflow.new(['-i', 'develop'])
    
    jw.expects(:set_init).with('develop')
    
    assert_equal 0, jw.run
  end

  def test_run_with_reset_option
    # Test run method with -r option
    jw = JiraWorkflow.new(['-r'])
    
    jw.expects(:reset_config)
    
    assert_equal 0, jw.run
  end

  def test_run_with_commit_msg_option
    # Test run method with --commit-msg-hook option
    jw = JiraWorkflow.new(['--commit-msg-hook'])
    
    jw.expects(:set_commit_msg).with(ARGV)
    
    assert_equal 0, jw.run
  end

  def test_run_with_empty_argv
    # Test run method with no arguments (displays config)
    jw = JiraWorkflow.new([])
    
    jw.expects(:display_jira_workflow_configs)
    
    assert_equal 0, jw.run
  end

  def test_run_with_jira_key
    # Test run method with JIRA key argument
    # Note: OptionParser.parse! modifies ARGV, removing parsed options but leaving non-option arguments
    # So 'TEST-123' will remain in ARGV after parsing
    original_argv = ARGV.dup
    begin
      ARGV.replace(['TEST-123'])
      jw = JiraWorkflow.new(['TEST-123'])
      
      jw.expects(:set_jira_workflow_configs).with('TEST-123')
      
      assert_equal 0, jw.run
    ensure
      ARGV.replace(original_argv)
    end
  end

  def test_update_commit_sha_with_partial_sha_match
    # Test update_commit_sha when SHA starts with HEAD (partial match)
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Set up JIRA key in config
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    
    original_msg = 'Original commit message'
    expected_msg = "[#{@jira_key}] #{original_msg}"
    escaped_msg = expected_msg.gsub(/'/, "'\\''")
    current_head = 'abc123'  # Partial match
    
    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns(original_msg)
    
    # Mock git rev-parse HEAD to return partial match
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(current_head)
    
    # Mock git commit --amend (should use amend because sha.start_with?(current_head))
    JiraWorkflow.any_instance.expects(:system).with("git commit --amend -m '#{escaped_msg}'").returns(true)
    
    # Mock puts
    JiraWorkflow.any_instance.expects(:puts).with("Commit message updated for HEAD")
    
    jw.update_commit_sha(@commit_sha)
  end

  def test_update_commit_sha_rebase_with_continue
    # Test update_commit_sha when rebase needs to continue
    jw = JiraWorkflow.new(['-s', @commit_sha])
    
    # Set up JIRA key in config
    jw.instance_variable_get(:@jw_config).set('key', @jira_key)
    
    original_msg = 'Original commit message'
    parent_sha = 'parent123'
    current_head = 'head789'
    
    # Mock git rev-parse to verify commit exists
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify '#{@commit_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git log to get commit message
    JiraWorkflow.any_instance.expects(:`).with("git log -1 --pretty=%B '#{@commit_sha}'").returns(original_msg)
    
    # Mock git rev-parse HEAD to return different SHA
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse HEAD").returns(current_head)
    
    # Mock git rev-parse to get parent
    JiraWorkflow.any_instance.expects(:`).with("git rev-parse '#{@commit_sha}^' 2>/dev/null").returns(parent_sha)
    
    # Mock File.write for temp scripts
    File.expects(:write).at_least_once
    File.expects(:chmod).at_least_once
    
    # Mock git rebase -i
    JiraWorkflow.any_instance.expects(:system).with(anything, "git rebase -i '#{parent_sha}' > /dev/null 2>&1").returns(true)
    
    # Mock git rev-parse to check for REBASE_HEAD (returns true - rebase needs to continue)
    JiraWorkflow.any_instance.expects(:system).with("git rev-parse --verify REBASE_HEAD > /dev/null 2>&1").returns(true)
    
    # Mock git rebase --continue
    JiraWorkflow.any_instance.expects(:system).with("git rebase --continue > /dev/null 2>&1").returns(true)
    
    # Mock File.exist? and File.delete for cleanup
    File.expects(:exist?).at_least_once.returns(true)
    File.expects(:delete).at_least_once
    
    # Mock puts
    JiraWorkflow.any_instance.expects(:puts).with("Commit message updated for SHA #{@short_sha}")
    
    jw.update_commit_sha(@commit_sha)
  end
end

require 'test/unit'
require 'mocha/test_unit'

# Load the GitHelper class from the script
load File.expand_path('../bin/jw', __dir__)

class GitHelperTest < Test::Unit::TestCase
  def setup
    @rc = JwRcConfig.new({})
    @jw_config = JwConfig.new(@rc)
    @git_helper = GitHelper.new(@rc, @jw_config)
    @jira_key = 'TEST-123'
  end

  def test_default_branch_returns_config_value
    # Mock the config to return a specific default branch
    @jw_config.expects(:get).with('default-branch').returns('develop')
    
    assert_equal 'develop', @git_helper.default_branch
  end

  def test_default_branch_returns_main_when_config_is_nil
    # Mock the config to return nil
    @jw_config.expects(:get).with('default-branch').returns(nil)
    
    assert_equal 'main', @git_helper.default_branch
  end

  def test_default_branch_returns_main_when_config_is_empty_string
    # Mock the config to return empty string
    # Note: In Ruby, empty string is truthy, so the || operator won't work
    # The actual implementation should handle this case properly
    @jw_config.expects(:get).with('default-branch').returns('')
    
    # The current implementation returns empty string for empty string input
    # This test documents the current behavior
    assert_equal 'main', @git_helper.default_branch
  end

  def test_create_branch_with_new_branch
    # Mock git branch --list to return empty (branch doesn't exist)
    GitHelper.any_instance.expects(:`).with("git branch --list feature/#{@jira_key}").returns('')
    
    # Mock the system call for creating a new branch
    expected_command = "git stash && git checkout main && git pull && git checkout -b feature/#{@jira_key} && git stash pop"
    GitHelper.any_instance.expects(:system).with(expected_command).returns(true)
    
    # Mock default_branch to return 'main' (called once in the if branch)
    @git_helper.expects(:default_branch).returns('main').once
    
    @git_helper.create_branch(@jira_key)
  end

  def test_create_branch_with_existing_branch
    # Mock git branch --list to return the branch name (branch exists)
    GitHelper.any_instance.expects(:`).with("git branch --list feature/#{@jira_key}").returns("feature/#{@jira_key}")
    
    # Mock the system call for switching to existing branch and rebasing
    expected_command = "git stash && git checkout main && git pull && git checkout feature/#{@jira_key} && git rebase main && git stash pop"
    GitHelper.any_instance.expects(:system).with(expected_command).returns(true)
    
    # Mock default_branch to return 'main' (called twice - once in if, once in else)
    @git_helper.expects(:default_branch).returns('main').twice
    
    @git_helper.create_branch(@jira_key)
  end

  def test_create_branch_with_custom_git_branch_prefix
    # Create a new GitHelper with custom git_branch_prefix
    custom_rc = JwRcConfig.new({ 'git_branch_prefix' => 'bugfix' })
    custom_git_helper = GitHelper.new(custom_rc, @jw_config)
    
    # Mock git branch --list to return empty (branch doesn't exist)
    GitHelper.any_instance.expects(:`).with("git branch --list bugfix/#{@jira_key}").returns('')
    
    # Mock the system call for creating a new branch
    expected_command = "git stash && git checkout main && git pull && git checkout -b bugfix/#{@jira_key} && git stash pop"
    GitHelper.any_instance.expects(:system).with(expected_command).returns(true)
    
    # Mock default_branch to return 'main' (called once in the if branch)
    custom_git_helper.expects(:default_branch).returns('main').once
    
    custom_git_helper.create_branch(@jira_key)
  end

  def test_create_branch_with_custom_default_branch
    # Mock default_branch to return 'develop' (called once in the if branch)
    @git_helper.expects(:default_branch).returns('develop').once
    
    # Mock git branch --list to return empty (branch doesn't exist)
    GitHelper.any_instance.expects(:`).with("git branch --list feature/#{@jira_key}").returns('')
    
    # Mock the system call for creating a new branch with custom default branch
    expected_command = "git stash && git checkout develop && git pull && git checkout -b feature/#{@jira_key} && git stash pop"
    GitHelper.any_instance.expects(:system).with(expected_command).returns(true)
    
    @git_helper.create_branch(@jira_key)
  end

  def test_create_branch_with_existing_branch_and_custom_default_branch
    # Mock default_branch to return 'develop' (called twice - once in if, once in else)
    @git_helper.expects(:default_branch).returns('develop').twice
    
    # Mock git branch --list to return the branch name (branch exists)
    GitHelper.any_instance.expects(:`).with("git branch --list feature/#{@jira_key}").returns("feature/#{@jira_key}")
    
    # Mock the system call for switching to existing branch and rebasing with custom default branch
    expected_command = "git stash && git checkout develop && git pull && git checkout feature/#{@jira_key} && git rebase develop && git stash pop"
    GitHelper.any_instance.expects(:system).with(expected_command).returns(true)
    
    @git_helper.create_branch(@jira_key)
  end

  def test_create_branch_handles_system_command_failure
    # Mock git branch --list to return empty (branch doesn't exist)
    GitHelper.any_instance.expects(:`).with("git branch --list feature/#{@jira_key}").returns('')
    
    # Mock the system call to return false (command failed)
    expected_command = "git stash && git checkout main && git pull && git checkout -b feature/#{@jira_key} && git stash pop"
    GitHelper.any_instance.expects(:system).with(expected_command).returns(false)
    
    # Mock default_branch to return 'main' (called once in the if branch)
    @git_helper.expects(:default_branch).returns('main').once
    
    # The method should not raise an error even if the system command fails
    assert_nothing_raised do
      @git_helper.create_branch(@jira_key)
    end
  end

  def test_initialize_with_rc_and_jw_config
    # Test that the GitHelper can be initialized with rc and jw_config
    assert_not_nil @git_helper
    assert_equal @rc, @git_helper.instance_variable_get(:@rc)
    assert_equal @jw_config, @git_helper.instance_variable_get(:@jw_config)
  end
end 
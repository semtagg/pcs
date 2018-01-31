require 'test/unit'
require 'fileutils'
require 'thread'

require 'pcsd_test_utils.rb'
require 'cfgsync.rb'
require 'config.rb'


class TestCfgsync < Test::Unit::TestCase
  def test_compare_version()
    cfg1 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="1" name="test1"/>'
    )
    cfg2 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="1" name="test1"/>'
    )
    cfg3 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="2" name="test1"/>'
    )
    cfg4 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="2" name="test2"/>'
    )

    assert(cfg1 == cfg2)
    assert(cfg1 < cfg3)
    assert(cfg1 < cfg4)
    assert(cfg3 > cfg1)
    assert_equal("0ebab34c8034fd1cb268d1170de935a183d156cf", cfg3.hash)
    assert_equal("0f22e8a496ae00815d8bcbf005fd7b645ba9f617", cfg4.hash)
    assert(cfg3 < cfg4)

    newest = [cfg1, cfg2, cfg3, cfg4].shuffle!.max
    assert_equal(2, newest.version)
    assert_equal('0f22e8a496ae00815d8bcbf005fd7b645ba9f617', newest.hash)
  end
end


class TestClusterConf < Test::Unit::TestCase
  def setup()
    FileUtils.cp(File.join(CURRENT_DIR, "cluster.conf"), CFG_CLUSTER_CONF)
  end

  def test_basics()
    assert_equal("cluster.conf", Cfgsync::ClusterConf.name)
    text = '<cluster config_version="3" name="test1"/>'

    cfg = Cfgsync::ClusterConf.from_text(text)
    assert_equal(text, cfg.text)
    assert_equal(3, cfg.version)
    assert_equal("1c0ff62f0749bea0b877599a02f6557573f286e2", cfg.hash)

    cfg.version = 4
    assert_equal(4, cfg.version)
    assert_equal("<cluster config_version='4' name='test1'/>", cfg.text)
    assert_equal('589e22aaff926907cc1f4db48eeeb5e269e41c39', cfg.hash)

    assert_equal(4, cfg.version)
    assert_equal("<cluster config_version='4' name='test1'/>", cfg.text)
    assert_equal('589e22aaff926907cc1f4db48eeeb5e269e41c39', cfg.hash)
  end

  def test_file()
    cfg = Cfgsync::ClusterConf.from_file()
    assert_equal(9, cfg.version)
    assert_equal("198bda4b748ef646de867cb850cd3ad208c36d8b", cfg.hash)
  end
end


class TestCorosyncConf < Test::Unit::TestCase
  def setup()
    FileUtils.cp(File.join(CURRENT_DIR, 'corosync.conf'), CFG_COROSYNC_CONF)
  end

  def test_basics()
    assert_equal('corosync.conf', Cfgsync::CorosyncConf.name)
    text = '
totem {
    version: 2
    cluster_name: test99
    config_version: 3
}
'
    cfg = Cfgsync::CorosyncConf.from_text(text)
    assert_equal(3, cfg.version)
    assert_equal('570c9f0324f1dec73a632fa9ae4a0dd53ebf8bc7', cfg.hash)

    cfg.version = 4
    assert_equal(4, cfg.version)
    assert_equal('efe2fc7d92ddf17ba1f14f334004c7c1933bb1e3', cfg.hash)

    cfg.text = "\
totem {
    version: 2
    cluster_name: test99
    config_version: 4
}
"
    assert_equal(4, cfg.version)
    assert_equal('efe2fc7d92ddf17ba1f14f334004c7c1933bb1e3', cfg.hash)
  end

  def test_file()
    cfg = Cfgsync::CorosyncConf.from_file()
    assert_equal(9, cfg.version)
    assert_equal('cd8faaf2367ceafba281387fb9dfe70eba51769c', cfg.hash)
  end

  def test_version()
    text = '
totem {
    version: 2
    cluster_name: test99
}
'
    cfg = Cfgsync::CorosyncConf.from_text(text)
    assert_equal(0, cfg.version)

    text = '
totem {
    version: 2
    cluster_name: test99
    config_version: 3
    config_version: 4
}
'
    cfg = Cfgsync::CorosyncConf.from_text(text)
    assert_equal(4, cfg.version)

    text = '
totem {
    version: 2
    cluster_name: test99
    config_version: foo
}
'
    cfg = Cfgsync::CorosyncConf.from_text(text)
    assert_equal(0, cfg.version)

    text = '
totem {
    version: 2
    cluster_name: test99
    config_version: 1foo
}
'
    cfg = Cfgsync::CorosyncConf.from_text(text)
    assert_equal(1, cfg.version)
  end
end


class TestPcsdSettings < Test::Unit::TestCase
  def teardown()
    FileUtils.rm(CFG_PCSD_SETTINGS, {:force => true})
  end

  def test_basics()
    assert_equal("pcs_settings.conf", Cfgsync::PcsdSettings.name)
    text = '
{
  "format_version": 2,
  "data_version": 3,
  "clusters": [
    {
      "name": "cluster71",
      "nodes": [
        "rh71-node1",
        "rh71-node2"
      ]
    }
  ],
  "permissions": {
    "local_cluster": [

    ]
  }
}
    '

    cfg = Cfgsync::PcsdSettings.from_text(text)
    assert_equal(text, cfg.text)
    assert_equal(3, cfg.version)
    assert_equal('b35f951a228ac0734d4c1e45fe73c03b18bca380', cfg.hash)

    cfg.version = 4
    assert_equal(4, cfg.version)
    assert_equal('26579b79a27f9f56e1acd398eb761d2eb1872c6d', cfg.hash)

    cfg.text = '{
  "format_version": 2,
  "data_version": 4,
  "clusters": [
    {
      "name": "cluster71",
      "nodes": [
        "rh71-node1",
        "rh71-node2"
      ]
    }
  ]
}'
    assert_equal(4, cfg.version)
    assert_equal('efe28c6d63dbce02da1a414ddb68fa1fc4f89c2e', cfg.hash)
  end

  def test_file()
    FileUtils.cp(File.join(CURRENT_DIR, "pcs_settings.conf"), CFG_PCSD_SETTINGS)
    cfg = Cfgsync::PcsdSettings.from_file()
    assert_equal(9, cfg.version)
    assert_equal("ac032803c5190d735cd94a702d42c5c6358013b8", cfg.hash)
  end

  def test_file_missing()
    cfg = Cfgsync::PcsdSettings.from_file()
    assert_equal(0, cfg.version)
    assert_equal('da39a3ee5e6b4b0d3255bfef95601890afd80709', cfg.hash)
  end
end


class TestPcsdTokens < Test::Unit::TestCase
  def teardown()
    FileUtils.rm(CFG_PCSD_TOKENS, {:force => true})
  end

  def test_basics()
    assert_equal('tokens', Cfgsync::PcsdTokens.name)
    text =
'{
  "format_version": 3,
  "data_version": 3,
  "tokens": {
    "rh7-1": "token-rh7-1",
    "rh7-2": "token-rh7-2"
  },
  "ports": {
    "rh7-1": "1234",
    "rh7-2": null
  }
}'

    cfg = Cfgsync::PcsdTokens.from_text(text)
    assert_equal(text, cfg.text)
    assert_equal(3, cfg.version)
    assert_equal('aedd225c15fb8cc41c1a34a5dd42b9f403ebc0de', cfg.hash)

    cfg.version = 4
    assert_equal(4, cfg.version)
    assert_equal('365d26bdf61966f8372ec23cdefd2a7cb235de02', cfg.hash)

    cfg.text =
'{
  "format_version": 3,
  "data_version": 4,
  "tokens": {
    "rh7-1": "token-rh7-1",
    "rh7-2": "token-rh7-2"
  },
  "ports": {
    "rh7-1": "1234",
    "rh7-2": null
  }
}'
    assert_equal(4, cfg.version)
    assert_equal('365d26bdf61966f8372ec23cdefd2a7cb235de02', cfg.hash)
  end

  def test_file()
    FileUtils.cp(File.join(CURRENT_DIR, 'tokens'), CFG_PCSD_TOKENS)
    cfg = Cfgsync::PcsdTokens.from_file()
    assert_equal(9, cfg.version)
    assert_equal('1ddfeb1a7ada600356945344bd3c137c09cf5845', cfg.hash)
  end

  def test_file_missing()
    cfg = Cfgsync::PcsdTokens.from_file()
    assert_equal(0, cfg.version)
    assert_equal('da39a3ee5e6b4b0d3255bfef95601890afd80709', cfg.hash)
  end
end


class TestPcsdKnownHosts < Test::Unit::TestCase
  def teardown()
    FileUtils.rm(CFG_PCSD_KNOWN_HOSTS, {:force => true})
  end

  def test_basics()
    assert_equal('known-hosts', Cfgsync::PcsdKnownHosts.name)
    template =
'{
  "format_version": 1,
  "data_version": %d,
  "known_hosts": {
    "node1": {
      "addr_port_list": [
        {
          "addr": "10.0.1.1",
          "port": 2224
        }
      ],
      "token": "abcde"
    }
  }
}'

    text = template % 2
    cfg = Cfgsync::PcsdKnownHosts.from_text(text)
    assert_equal(text, cfg.text)
    assert_equal(2, cfg.version)
    assert_equal('9730e692503d9af5163d18e21bee4e9749cbdd62', cfg.hash)

    cfg.version = 3
    assert_equal(3, cfg.version)
    assert_equal('0082830bf2504d6a4025b65f6272df0dc188710b', cfg.hash)

    cfg.text = template % 4
    assert_equal(4, cfg.version)
    assert_equal('064c134ffd43a16a70f03e7558ea56b1d49ec964', cfg.hash)
  end

  def test_file()
    FileUtils.cp(File.join(CURRENT_DIR, 'known-hosts'), CFG_PCSD_KNOWN_HOSTS)
    cfg = Cfgsync::PcsdKnownHosts.from_file()
    assert_equal(5, cfg.version)
    assert_equal('69482ef019603264ea24005ee90be9b5ab5c2910', cfg.hash)
  end

  def test_file_missing()
    cfg = Cfgsync::PcsdKnownHosts.from_file()
    assert_equal(0, cfg.version)
    assert_equal('da39a3ee5e6b4b0d3255bfef95601890afd80709', cfg.hash)
  end
end

class TestConfigSyncControll < Test::Unit::TestCase
  def setup()
    file = File.open(CFG_SYNC_CONTROL, 'w')
    file.write(JSON.pretty_generate({}))
    file.close()
    @thread_interval_default = 60
    @thread_interval_minimum = 20
    @file_backup_count_default = 50
    @file_backup_count_minimum = 0
  end

  def test_bad_file()
    FileUtils.rm(CFG_SYNC_CONTROL, {:force => true})
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())
    assert_equal(
      @thread_interval_default,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )

    file = File.open(CFG_SYNC_CONTROL, 'w')
    file.write('')
    file.close()
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())
    assert_equal(
      @thread_interval_default,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )

    file = File.open(CFG_SYNC_CONTROL, 'w')
    file.write(JSON.pretty_generate({
      'thread_paused_until' => 'abcde',
      'thread_interval' => 'fghij',
    }))
    file.close()
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())
    assert_equal(
      @thread_interval_default,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )
  end

  def test_empty_file()
    # see setup method
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())
    assert_equal(
      @thread_interval_default,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )
  end

  def test_paused()
    semaphore = Mutex.new

    assert(Cfgsync::ConfigSyncControl.sync_thread_resume())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())

    assert(Cfgsync::ConfigSyncControl.sync_thread_pause(semaphore))
    assert(Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_allowed?())

    assert(Cfgsync::ConfigSyncControl.sync_thread_resume())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())

    assert(Cfgsync::ConfigSyncControl.sync_thread_pause(semaphore, 2))
    assert(Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_allowed?())
    sleep(4)
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())

    assert(Cfgsync::ConfigSyncControl.sync_thread_pause(semaphore, '2'))
    assert(Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_allowed?())
    sleep(4)
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())

    assert(Cfgsync::ConfigSyncControl.sync_thread_pause(semaphore, 'abcd'))
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())
  end

  def test_disable()
    semaphore = Mutex.new

    assert(Cfgsync::ConfigSyncControl.sync_thread_enable())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())

    assert(Cfgsync::ConfigSyncControl.sync_thread_disable(semaphore))
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_allowed?())

    assert(Cfgsync::ConfigSyncControl.sync_thread_enable())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_paused?())
    assert(!Cfgsync::ConfigSyncControl.sync_thread_disabled?())
    assert(Cfgsync::ConfigSyncControl.sync_thread_allowed?())
  end

  def test_interval()
    assert_equal(
      @thread_interval_default,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )

    interval = @thread_interval_default + @thread_interval_minimum
    assert(Cfgsync::ConfigSyncControl.sync_thread_interval=(interval))
    assert_equal(
      interval,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )

    assert(Cfgsync::ConfigSyncControl.sync_thread_interval=(
      @thread_interval_minimum / 2
    ))
    assert_equal(
      @thread_interval_minimum,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )

    assert(Cfgsync::ConfigSyncControl.sync_thread_interval=(0))
    assert_equal(
      @thread_interval_minimum,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )

    assert(Cfgsync::ConfigSyncControl.sync_thread_interval=(-100))
    assert_equal(
      @thread_interval_minimum,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )

    assert(Cfgsync::ConfigSyncControl.sync_thread_interval=('abcd'))
    assert_equal(
      @thread_interval_default,
      Cfgsync::ConfigSyncControl.sync_thread_interval()
    )
  end

  def test_file_backup_count()
    assert_equal(
      @file_backup_count_default,
      Cfgsync::ConfigSyncControl.file_backup_count()
    )

    count = @file_backup_count_default + @file_backup_count_minimum
    assert(Cfgsync::ConfigSyncControl.file_backup_count=(count))
    assert_equal(
      count,
      Cfgsync::ConfigSyncControl.file_backup_count()
    )

    assert(Cfgsync::ConfigSyncControl.file_backup_count=(
      @file_backup_count_minimum / 2
    ))
    assert_equal(
      @file_backup_count_minimum,
      Cfgsync::ConfigSyncControl.file_backup_count()
    )

    assert(Cfgsync::ConfigSyncControl.file_backup_count=(0))
    assert_equal(
      @file_backup_count_minimum,
      Cfgsync::ConfigSyncControl.file_backup_count()
    )

    assert(Cfgsync::ConfigSyncControl.file_backup_count=(-100))
    assert_equal(
      @file_backup_count_minimum,
      Cfgsync::ConfigSyncControl.file_backup_count()
    )

    assert(Cfgsync::ConfigSyncControl.file_backup_count=('abcd'))
    assert_equal(
      @file_backup_count_default,
      Cfgsync::ConfigSyncControl.file_backup_count()
    )
  end
end


class TestConfigFetcher < Test::Unit::TestCase
  class ConfigFetcherMock < Cfgsync::ConfigFetcher
    def get_configs_local()
      return @configs_local
    end

    def set_configs_local(configs)
      @configs_local = configs
      return self
    end

    def get_configs_cluster(nodes, cluster_name)
      return @configs_cluster
    end

    def set_configs_cluster(configs)
      @configs_cluster = configs
      return self
    end

    def find_newest_config_test(config_list)
      return self.find_newest_config(config_list)
    end
  end

  def test_find_newest_config()
    cfg1 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="1" name="test1"/>'
    )
    cfg2 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="1" name="test1"/>'
    )
    cfg3 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="2" name="test1"/>'
    )
    cfg4 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="2" name="test2"/>'
    )
    assert(cfg1 == cfg2)
    assert(cfg1 < cfg3)
    assert(cfg1 < cfg4)
    assert(cfg3 < cfg4)
    fetcher = ConfigFetcherMock.new({}, nil, nil, nil)

    # trivial case
    assert_equal(cfg1, fetcher.find_newest_config_test([cfg1]))
    # decide by version only
    assert_equal(cfg3, fetcher.find_newest_config_test([cfg1, cfg2, cfg3]))
    assert_equal(cfg3, fetcher.find_newest_config_test([cfg1, cfg1, cfg3]))
    # in case of multiple configs with the same version decide by count
    assert_equal(cfg3, fetcher.find_newest_config_test([cfg3, cfg3, cfg4]))
    assert_equal(
      cfg3, fetcher.find_newest_config_test([cfg1, cfg3, cfg3, cfg4])
    )
    # if the count is the same decide by hash
    assert(cfg3 < cfg4)
    assert_equal(cfg4, fetcher.find_newest_config_test([cfg3, cfg4]))
    assert_equal(cfg4, fetcher.find_newest_config_test([cfg1, cfg3, cfg4]))
    assert_equal(
      cfg4, fetcher.find_newest_config_test([cfg3, cfg3, cfg4, cfg4])
    )
    assert_equal(
      cfg4, fetcher.find_newest_config_test([cfg1, cfg3, cfg3, cfg4, cfg4])
    )
  end

  def test_fetch()
    cfg1 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="1" name="test1"/>'
    )
    cfg2 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="1" name="test1"/>'
    )
    cfg3 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="2" name="test1"/>'
    )
    cfg4 = Cfgsync::ClusterConf.from_text(
      '<cluster config_version="2" name="test2"/>'
    )
    assert(cfg1 == cfg2)
    assert(cfg1 < cfg3)
    assert(cfg1 < cfg4)
    assert(cfg3 < cfg4)
    cfg_name = Cfgsync::ClusterConf.name
    fetcher = ConfigFetcherMock.new({}, [Cfgsync::ClusterConf], nil, nil)

    # local config is synced
    fetcher.set_configs_local({cfg_name => cfg1})

    fetcher.set_configs_cluster({
      'node1' => {'configs' => {cfg_name => cfg1}},
    })
    assert_equal([[], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {'configs' => {cfg_name => cfg2}},
    })
    assert_equal([[], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {'configs' => {cfg_name => cfg1}},
      'node2' => {'configs' => {cfg_name => cfg2}},
    })
    assert_equal([[], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {'configs' => {cfg_name => cfg1}},
      'node2' => {'configs' => {cfg_name => cfg2}},
      'node3' => {'configs' => {cfg_name => cfg2}},
    })
    assert_equal([[], []], fetcher.fetch())

    # local config is older
    fetcher.set_configs_local({cfg_name => cfg1})

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
    })
    assert_equal([[cfg3], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
      'node2' => {cfg_name => cfg4},
    })
    assert_equal([[cfg4], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
      'node2' => {cfg_name => cfg4},
      'node3' => {cfg_name => cfg3},
    })
    assert_equal([[cfg3], []], fetcher.fetch())

    # local config is newer
    fetcher.set_configs_local({cfg_name => cfg3})

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg1},
    })
    assert_equal([[], [cfg3]], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg1},
      'node2' => {cfg_name => cfg1},
    })
    assert_equal([[], [cfg3]], fetcher.fetch())

    # local config is the same version
    fetcher.set_configs_local({cfg_name => cfg3})

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
    })
    assert_equal([[], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg4},
    })
    assert_equal([[cfg4], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
      'node2' => {cfg_name => cfg4},
    })
    assert_equal([[cfg4], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
      'node2' => {cfg_name => cfg4},
      'node3' => {cfg_name => cfg3},
    })
    assert_equal([[], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
      'node2' => {cfg_name => cfg4},
      'node3' => {cfg_name => cfg4},
    })
    assert_equal([[cfg4], []], fetcher.fetch())

    # local config is the same version
    fetcher.set_configs_local({cfg_name => cfg4})

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
    })
    assert_equal([[cfg3], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg4},
    })
    assert_equal([[], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
      'node2' => {cfg_name => cfg4},
    })
    assert_equal([[], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
      'node2' => {cfg_name => cfg4},
      'node3' => {cfg_name => cfg3},
    })
    assert_equal([[cfg3], []], fetcher.fetch())

    fetcher.set_configs_cluster({
      'node1' => {cfg_name => cfg3},
      'node2' => {cfg_name => cfg4},
      'node3' => {cfg_name => cfg4},
    })
    assert_equal([[], []], fetcher.fetch())
  end
end


class TestMergeKnownHosts < Test::Unit::TestCase
  def setup()
    FileUtils.cp(File.join(CURRENT_DIR, 'known-hosts'), CFG_PCSD_KNOWN_HOSTS)
  end

  def teardown()
    FileUtils.rm(CFG_PCSD_KNOWN_HOSTS, {:force => true})
  end

  def fixture_old_cfg()
    return (
'{
  "format_version": 1,
  "data_version": 5,
  "known_hosts": {
    "node1": {
      "addr_port_list": [
        {
          "addr": "10.0.1.1",
          "port": 2224
        }
      ],
      "token": "token1"
    },
    "node2": {
      "addr_port_list": [
        {
          "addr": "10.0.1.2",
          "port": 2234
        },
        {
          "addr": "10.0.2.2",
          "port": 2235
        }
      ],
      "token": "token2"
    }
  }
}')
  end

  def fixture_new_cfg(version=5)
    return (
'{
  "format_version": 1,
  "data_version": %d,
  "known_hosts": {
    "node1": {
      "addr_port_list": [
        {
          "addr": "10.0.1.1",
          "port": 2224
        }
      ],
      "token": "token1"
    },
    "node2": {
      "addr_port_list": [
        {
          "addr": "10.0.1.2",
          "port": 2224
        }
      ],
      "token": "token2a"
    },
    "node3": {
      "addr_port_list": [
        {
          "addr": "10.0.1.3",
          "port": 2224
        }
      ],
      "token": "token3"
    }
  }
}' % version)
  end

  def fixture_node2()
    return PcsKnownHost.new(
      'node2',
      'token2a',
      [
        {'addr' => '10.0.1.2', 'port' => 2224}
      ]
    )
  end

  def fixture_node3()
    return PcsKnownHost.new(
      'node3',
      'token3',
      [
        {'addr' => '10.0.1.3', 'port' => 2224}
      ]
    )
  end

  def fixture_old_text()
    return (
'{
  "format_version": 1,
  "data_version": 2,
  "known_hosts": {
    "node1": {
      "addr_port_list": [
        {
          "addr": "10.0.1.1",
          "port": 2224
        }
      ],
      "token": "token1a"
  }
}')
  end

  def test_nothing_to_merge()
    old_cfg = Cfgsync::PcsdKnownHosts.from_text(fixture_old_cfg())
    new_cfg = Cfgsync::merge_known_host_files(old_cfg, nil, [])
    assert_equal(old_cfg.text.strip, new_cfg.text.strip)
  end

  def test_extra_hosts()
    old_cfg = Cfgsync::PcsdKnownHosts.from_text(fixture_old_cfg())
    new_cfg = Cfgsync::merge_known_host_files(
      old_cfg,
      [],
      [fixture_node2(), fixture_node3()]
    )
    assert_equal(fixture_new_cfg, new_cfg.text.strip)
  end

  def test_older_file()
    old_cfg = Cfgsync::PcsdKnownHosts.from_text(fixture_old_cfg())
    new_cfg = Cfgsync::merge_known_host_files(
      old_cfg,
      [Cfgsync::PcsdKnownHosts.from_text(fixture_old_text)],
      []
    )
    assert_equal(old_cfg.text.strip, new_cfg.text.strip)
  end

  def test_older_file_and_extra_hosts()
    old_cfg = Cfgsync::PcsdKnownHosts.from_text(fixture_old_cfg())
    new_cfg = Cfgsync::merge_known_host_files(
      old_cfg,
      [Cfgsync::PcsdKnownHosts.from_text(fixture_old_text)],
      [fixture_node2(), fixture_node3()]
    )
    assert_equal(fixture_new_cfg, new_cfg.text.strip)
  end

  def test_newer_file()
    new_text =
'{
  "format_version": 1,
  "data_version": 7,
  "known_hosts": {
    "node2": {
      "addr_port_list": [
        {
          "addr": "10.0.1.2",
          "port": 2224
        }
      ],
      "token": "token2a"
    },
    "node3": {
      "addr_port_list": [
        {
          "addr": "10.0.1.3",
          "port": 2224
        }
      ],
      "token": "token3"
    }
  }
}'
    old_cfg = Cfgsync::PcsdKnownHosts.from_text(fixture_old_cfg())
    new_cfg = Cfgsync::merge_known_host_files(
      old_cfg,
      [Cfgsync::PcsdKnownHosts.from_text(new_text)],
      []
    )
    assert_equal(fixture_new_cfg(7), new_cfg.text.strip)
  end

  def test_newer_file_and_extra_hosts()
    new_text =
'{
  "format_version": 1,
  "data_version": 7,
  "known_hosts": {
    "node2": {
      "addr_port_list": [
        {
          "addr": "10.0.122.2",
          "port": 2224
        }
      ],
      "token": "token2aaaaaaaa"
    },
    "node3": {
      "addr_port_list": [
        {
          "addr": "10.0.1.3",
          "port": 2224
        }
      ],
      "token": "token3"
    }
  }
}'
    old_cfg = Cfgsync::PcsdKnownHosts.from_text(fixture_old_cfg())
    new_cfg = Cfgsync::merge_known_host_files(
      old_cfg,
      [Cfgsync::PcsdKnownHosts.from_text(new_text)],
      [fixture_node2()]
    )
    assert_equal(fixture_new_cfg(7), new_cfg.text.strip)
  end

  def test_newer_files()
    new_text1 =
'{
  "format_version": 1,
  "data_version": 6,
  "known_hosts": {
    "node2": {
      "addr_port_list": [
        {
          "addr": "10.0.1.2",
          "port": 2224
        }
      ],
      "token": "token2aaaaaaaaaa"
    },
    "node3": {
      "addr_port_list": [
        {
          "addr": "10.0.1.3",
          "port": 2224
        }
      ],
      "token": "token3"
    }
  }
}'
    new_text2 =
'{
  "format_version": 1,
  "data_version": 7,
  "known_hosts": {
    "node2": {
      "addr_port_list": [
        {
          "addr": "10.0.1.2",
          "port": 2224
        }
      ],
      "token": "token2a"
    }
  }
}'
    old_cfg = Cfgsync::PcsdKnownHosts.from_text(fixture_old_cfg())
    new_cfg = Cfgsync::merge_known_host_files(
      old_cfg,
      [
        Cfgsync::PcsdKnownHosts.from_text(new_text1),
        Cfgsync::PcsdKnownHosts.from_text(new_text2),
      ],
      []
    )
    assert_equal(fixture_new_cfg(7), new_cfg.text.strip)
  end

  def test_newer_files_and_extra_hosts()
    new_text1 =
'{
  "format_version": 1,
  "data_version": 6,
  "known_hosts": {
    "node2": {
      "addr_port_list": [
        {
          "addr": "10.0.1.2",
          "port": 2224
        }
      ],
      "token": "token2aaaaaaaaaa"
    },
    "node3": {
      "addr_port_list": [
        {
          "addr": "10.0.1.3",
          "port": 2224
        }
      ],
      "token": "token3aaaaaaaaaa"
    }
  }
}'
    new_text2 =
'{
  "format_version": 1,
  "data_version": 7,
  "known_hosts": {
    "node2": {
      "addr_port_list": [
        {
          "addr": "10.0.1.2",
          "port": 2224
        }
      ],
      "token": "token2a"
    }
  }
}'
    old_cfg = Cfgsync::PcsdKnownHosts.from_text(fixture_old_cfg())
    new_cfg = Cfgsync::merge_known_host_files(
      old_cfg,
      [
        Cfgsync::PcsdKnownHosts.from_text(new_text1),
        Cfgsync::PcsdKnownHosts.from_text(new_text2),
      ],
      [fixture_node3()]
    )
    assert_equal(fixture_new_cfg(7), new_cfg.text.strip)
  end
end

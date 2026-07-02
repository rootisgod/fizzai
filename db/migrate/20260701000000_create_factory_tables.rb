class CreateFactoryTables < ActiveRecord::Migration[8.2]
  def change
    create_table :factory_skills, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.string :name, null: false
      t.text :description
      t.text :instructions
      t.boolean :active, null: false, default: true
      t.timestamps

      t.index [ :account_id, :name ], unique: true
      t.index [ :account_id, :active ]
    end

    create_table :factory_profiles, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.string :name, null: false
      t.text :description
      t.string :brain_provider, null: false, default: "codex_cli"
      t.string :brain_model, null: false, default: "gpt-5.4"
      t.text :brain_options
      t.text :prompt
      t.string :runner_kind, null: false, default: "sandcastle"
      t.text :verification_command
      t.integer :max_iterations, null: false, default: 1
      t.integer :max_attempts, null: false, default: 2
      t.boolean :active, null: false, default: true
      t.timestamps

      t.index [ :account_id, :name ], unique: true
      t.index [ :account_id, :active ]
    end

    create_table :factory_profile_skills, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :profile_id, null: false
      t.uuid :skill_id, null: false
      t.timestamps

      t.index [ :account_id, :profile_id ]
      t.index [ :account_id, :skill_id ]
      t.index [ :profile_id, :skill_id ], unique: true
    end

    create_table :factory_runners, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.string :name, null: false
      t.string :kind, null: false, default: "sandcastle"
      t.string :token, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_seen_at
      t.text :metadata
      t.timestamps

      t.index [ :account_id, :name ], unique: true
      t.index [ :account_id, :active ]
      t.index :token, unique: true
    end

    create_table :factory_card_dependencies, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :parent_card_id, null: false
      t.uuid :child_card_id, null: false
      t.timestamps

      t.index [ :account_id, :parent_card_id ]
      t.index [ :account_id, :child_card_id ]
      t.index [ :parent_card_id, :child_card_id ], unique: true
    end

    create_table :factory_runs, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :card_id, null: false
      t.uuid :profile_id, null: false
      t.uuid :runner_id
      t.uuid :requester_id
      t.string :state, null: false, default: "queued"
      t.integer :attempts_count, null: false, default: 0
      t.integer :max_attempts, null: false, default: 2
      t.integer :max_iterations, null: false, default: 1
      t.string :branch_name, null: false
      t.string :commit_sha
      t.text :verification_command
      t.string :verification_status
      t.text :summary
      t.text :failure_reason
      t.text :block_reason
      t.text :metadata
      t.datetime :claimed_at
      t.datetime :heartbeat_at
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps

      t.index [ :account_id, :state, :created_at ]
      t.index [ :account_id, :card_id ]
      t.index [ :account_id, :profile_id ]
      t.index [ :account_id, :runner_id ]
    end

    create_table :factory_run_logs, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :run_id, null: false
      t.string :stream, null: false
      t.integer :sequence, null: false
      t.text :content, null: false
      t.timestamps

      t.index [ :account_id, :run_id ]
      t.index [ :run_id, :sequence ], unique: true
    end
  end
end

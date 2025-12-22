require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) { described_class.new }

  describe '#generate_user_report' do
    let(:user_ids) { [1, 2] }

    let(:user_1) { instance_double('User', name: 'Alice', posts: posts_1) }
    let(:user_2) { instance_double('User', name: 'Bob', posts: posts_2) }

    let(:posts_1) { instance_double('PostsAssociation') }
    let(:posts_2) { instance_double('PostsAssociation') }

    before do
      stub_const('User', Class.new)

      allow(User).to receive(:find).with(1).and_return(user_1)
      allow(User).to receive(:find).with(2).and_return(user_2)

      allow(posts_1).to receive(:count).and_return(3)
      allow(posts_2).to receive(:count).and_return(0)

      allow(generator).to receive(:puts)
    end

    it 'finds each user by id and prints a line with name and post count' do
      generator.generate_user_report(user_ids)

      expect(User).to have_received(:find).with(1).once
      expect(User).to have_received(:find).with(2).once

      expect(generator).to have_received(:puts).with('Alice: 3 posts').once
      expect(generator).to have_received(:puts).with('Bob: 0 posts').once
    end

    it 'returns the original enumerable result of each (the ids array)' do
      result = generator.generate_user_report(user_ids)
      expect(result).to eq(user_ids)
    end

    context 'when user_ids is empty' do
      let(:user_ids) { [] }

      it 'does not query for users and does not print anything' do
        generator.generate_user_report(user_ids)

        expect(User).not_to have_received(:find)
        expect(generator).not_to have_received(:puts)
      end

      it 'returns the empty array' do
        expect(generator.generate_user_report(user_ids)).to eq([])
      end
    end

    context 'when user_ids is nil' do
      it 'raises NoMethodError because nil does not respond to each' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when User.find raises an error for an id' do
      let(:user_ids) { [1, 999] }

      before do
        allow(User).to receive(:find).with(999).and_raise(StandardError, 'not found')
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report(user_ids)
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'when posts association does not respond to count' do
      let(:posts_1) { Object.new }

      it 'raises NoMethodError while attempting to call count' do
        expect do
          generator.generate_user_report([1])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:record_1) { instance_double('Record', id: 10, name: 'Alpha') }
    let(:record_2) { instance_double('Record', id: 11, name: 'Beta') }

    it 'builds a CSV string with each record on its own line' do
      result = generator.build_csv([record_1, record_2])
      expect(result).to eq("10,Alpha\n11,Beta\n")
    end

    it 'returns an empty string when records is empty' do
      expect(generator.build_csv([])).to eq('')
    end

    context 'when records is nil' do
      it 'raises NoMethodError because nil does not respond to each' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record does not respond to id' do
      let(:bad_record) { instance_double('Record', name: 'NoID') }

      before do
        allow(bad_record).to receive(:id).and_raise(NoMethodError)
      end

      it 'raises NoMethodError' do
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record name is nil' do
      let(:record_with_nil_name) { instance_double('Record', id: 1, name: nil) }

      it 'includes an empty field for the nil name via string interpolation' do
        expect(generator.build_csv([record_with_nil_name])).to eq("1,\n")
      end
    end
  end

  describe '#find_matches' do
    it 'returns matching values from list_a that are present in list_b' do
      result = generator.find_matches([1, 2, 3], [2, 4, 3])
      expect(result).to eq([2, 3])
    end

    it 'returns an empty array when list_a is empty' do
      expect(generator.find_matches([], [1, 2, 3])).to eq([])
    end

    it 'returns an empty array when list_b is empty' do
      expect(generator.find_matches([1, 2, 3], [])).to eq([])
    end

    it 'returns duplicates when list_a contains duplicates that match list_b' do
      result = generator.find_matches([2, 2, 3], [2])
      expect(result).to eq([2, 2])
    end

    it 'returns duplicates when list_b contains duplicates for a single list_a match' do
      result = generator.find_matches([2], [2, 2, 2])
      expect(result).to eq([2, 2, 2])
    end

    it 'uses == for comparison and can match objects based on equality' do
      item_a = instance_double('ThingA')
      item_b = instance_double('ThingB')

      allow(item_a).to receive(:==).with(item_b).and_return(true)

      result = generator.find_matches([item_a], [item_b])
      expect(result).to eq([item_a])
      expect(item_a).to have_received(:==).with(item_b).at_least(:once)
    end

    context 'when list_a is nil' do
      it 'raises NoMethodError because nil does not respond to each' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end
    end

    context 'when list_b is nil' do
      it 'raises NoMethodError because nil does not respond to each' do
        expect do
          generator.find_matches([], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user_1) { instance_double('UserInstance') }
    let(:user_2) { instance_double('UserInstance') }
    let(:users_relation) { [user_1, user_2] }

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:all).and_return(users_relation)
      allow(generator).to receive(:send_email)
    end

    it 'iterates all users and sends an email to each one' do
      generator.process_all_users

      expect(User).to have_received(:all).once
      expect(generator).to have_received(:send_email).with(user_1).once
      expect(generator).to have_received(:send_email).with(user_2).once
    end

    it 'returns the original enumerable result of each (the users collection)' do
      result = generator.process_all_users
      expect(result).to eq(users_relation)
    end

    context 'when there are no users' do
      let(:users_relation) { [] }

      it 'does not send any emails' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when User.all raises an error' do
      before do
        allow(User).to receive(:all).and_raise(StandardError, 'db unavailable')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'db unavailable')
      end
    end

    context 'when send_email raises an error for a user' do
      before do
        allow(generator).to receive(:send_email).with(user_1).and_raise(StandardError, 'smtp error')
      end

      it 'propagates the error and stops processing' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'smtp error')

        expect(generator).to have_received(:send_email).with(user_1).once
        expect(generator).not_to have_received(:send_email).with(user_2)
      end
    end
  end
end

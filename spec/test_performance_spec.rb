require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    before do
      stub_const('User', Class.new)
    end

    context 'with multiple valid user ids' do
      let(:user_ids) do
        [1, 2, 3]
      end

      let(:users_map) do
        {
          1 => double('User1', name: 'User1'),
          2 => double('User2', name: 'User2'),
          3 => double('User3', name: 'User3')
        }
      end

      let(:posts_map) do
        {
          1 => double('Posts1', count: 10),
          2 => double('Posts2', count: 20),
          3 => double('Posts3', count: 30)
        }
      end

      before do
        users_map.each do |id, user_double|
          allow(user_double).to receive(:posts).and_return(posts_map[id])
          allow(posts_map[id]).to receive(:count).and_return(posts_map[id].count)
        end
        allow(User).to receive(:find) do |id|
          users_map[id]
        end
      end

      it 'queries each user and their posts and prints a line per user' do
        expected_output = "User1: 10 posts\nUser2: 20 posts\nUser3: 30 posts\n"
        expect do
          generator.generate_user_report(user_ids)
        end.to output(expected_output).to_stdout
        user_ids.each do |id|
          expect(User).to have_received(:find).with(id)
          expect(users_map[id]).to have_received(:posts)
          expect(posts_map[id]).to have_received(:count)
        end
      end
    end

    context 'with an empty user_ids array' do
      it 'produces no output and does not query the database' do
        allow(User).to receive(:find)
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
        expect(User).not_to have_received(:find)
      end
    end

    context 'when a user lookup raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:find) do |_id|
          raise StandardError, 'lookup failed'
        end
        expect do
          generator.generate_user_report([1])
        end.to raise_error(StandardError, 'lookup failed')
      end
    end

    context 'when user_ids is nil' do
      it 'raises a NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    context 'with valid records' do
      let(:record1) do
        Struct.new(:id, :name).new(1, 'Alice')
      end

      let(:record2) do
        Struct.new(:id, :name).new(2, 'Bob')
      end

      it 'returns a CSV string with each record on a new line' do
        csv = generator.build_csv([record1, record2])
        expect(csv).to eq("1,Alice\n2,Bob\n")
      end

      it 'handles names with commas without escaping (as-is behavior)' do
        r = Struct.new(:id, :name).new(3, 'Last, First')
        csv = generator.build_csv([r])
        expect(csv).to eq("3,Last, First\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        expect(generator.build_csv([])).to eq('')
      end
    end

    context 'when records is nil' do
      it 'raises a NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record does not respond to required methods' do
      it 'raises NoMethodError for missing id' do
        bad_record = Struct.new(:name).new('NoID')
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError for missing name' do
        bad_record = Struct.new(:id).new(123)
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping arrays' do
      it 'returns the intersection preserving multiplicity from list_b per occurrence' do
        list_a = [1, 2, 3]
        list_b = [2, 3, 4]
        expect(generator.find_matches(list_a, list_b)).to eq([2, 3])
      end
    end

    context 'with duplicates in list_b' do
      it 'includes duplicates for each matching occurrence in list_b' do
        list_a = [1, 2]
        list_b = [2, 2, 2]
        expect(generator.find_matches(list_a, list_b)).to eq([2, 2, 2])
      end
    end

    context 'with duplicates in list_a' do
      it 'includes duplicates for each matching occurrence in list_a' do
        list_a = [2, 2]
        list_b = [2]
        expect(generator.find_matches(list_a, list_b)).to eq([2, 2])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        expect(generator.find_matches([1, 5], [2, 3, 4])).to eq([])
      end
    end

    context 'with type mismatches' do
      it 'does not match values of different types' do
        expect(generator.find_matches([1, '2'], [2, '2'])).to eq(['2'])
      end
    end

    context 'with empty arrays' do
      it 'returns an empty array when list_a is empty' do
        expect(generator.find_matches([], [1, 2, 3])).to eq([])
      end

      it 'returns an empty array when list_b is empty' do
        expect(generator.find_matches([1, 2, 3], [])).to eq([])
      end
    end

    context 'when inputs are nil' do
      it 'raises NoMethodError for nil list_a' do
        expect do
          generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError for nil list_b' do
        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    before do
      stub_const('User', Class.new)
      allow(generator).to receive(:send_email)
    end

    context 'when there are users' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'sends an email to each user' do
        generator.process_all_users
        expect(generator).to have_received(:send_email).with(user1).once
        expect(generator).to have_received(:send_email).with(user2).once
      end
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not send any emails' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when send_email raises an error' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email) do |user|
          raise StandardError, 'email failed' if user == user1
        end
      end

      it 'propagates the error and stops processing' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'email failed')
        expect(generator).to have_received(:send_email).with(user1).once
      end
    end

    context 'when User.all returns nil' do
      before do
        allow(User).to receive(:all).and_return(nil)
      end

      it 'raises a NoMethodError' do
        expect do
          generator.process_all_users
        end.to raise_error(NoMethodError)
      end
    end
  end
end

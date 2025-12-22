require 'spec_helper'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    let(:out) do
      StringIO.new
    end

    before do
      @orig_stdout = $stdout
      $stdout = out
      stub_const('User', Class.new)
    end

    after do
      $stdout = @orig_stdout
    end

    context 'with multiple valid user ids' do
      let(:posts1) do
        double('Posts1', count: 3)
      end

      let(:posts2) do
        double('Posts2', count: 1)
      end

      let(:user1) do
        double('User1', name: 'Alice', posts: posts1)
      end

      let(:user2) do
        double('User2', name: 'Bob', posts: posts2)
      end

      let(:user_ids) do
        [10, 20]
      end

      before do
        allow(User).to receive(:find).with(10).and_return(user1)
        allow(User).to receive(:find).with(20).and_return(user2)
      end

      it 'queries each id, loads posts, and prints the report lines' do
        generator.generate_user_report(user_ids)
        expect(User).to have_received(:find).with(10)
        expect(User).to have_received(:find).with(20)
        expect(out.string).to include('Alice: 3 posts')
        expect(out.string).to include('Bob: 1 posts')
      end

      it 'calls posts.count for each user' do
        generator.generate_user_report(user_ids)
        expect(posts1).to have_received(:count).once
        expect(posts2).to have_received(:count).once
      end
    end

    context 'with duplicate user ids' do
      let(:posts) do
        double('Posts', count: 2)
      end

      let(:user) do
        double('User', name: 'Carol', posts: posts)
      end

      let(:user_ids) do
        [5, 5]
      end

      before do
        allow(User).to receive(:find).with(5).and_return(user)
      end

      it 'queries for each occurrence' do
        generator.generate_user_report(user_ids)
        expect(User).to have_received(:find).with(5).twice
        expect(out.string.scan('Carol: 2 posts').size).to eq(2)
      end
    end

    context 'with an empty array' do
      before do
        allow(User).to receive(:find)
      end

      it 'does nothing and prints nothing' do
        generator.generate_user_report([])
        expect(User).not_to have_received(:find)
        expect(out.string).to eq('')
      end
    end

    context 'with nil input' do
      it 'raises an error' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when User.find raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:find).with(99).and_raise(StandardError, 'not found')
        expect do
          generator.generate_user_report([99])
        end.to raise_error(StandardError, 'not found')
      end
    end
  end

  describe '#build_csv' do
    context 'with multiple records' do
      let(:record1) do
        double('Record1', id: 1, name: 'Alice')
      end

      let(:record2) do
        double('Record2', id: 2, name: 'Bob')
      end

      let(:records) do
        [record1, record2]
      end

      it 'returns a CSV string with one line per record' do
        csv = generator.build_csv(records)
        expect(csv).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty list' do
      it 'returns an empty string' do
        csv = generator.build_csv([])
        expect(csv).to eq('')
      end
    end

    context 'with nil fields' do
      let(:record) do
        double('Record', id: 3, name: nil)
      end

      it 'interpolates nil as empty string' do
        csv = generator.build_csv([record])
        expect(csv).to eq("3,\n")
      end
    end

    context 'with invalid record (missing attributes)' do
      let(:bad_record) do
        double('BadRecord', id: 4)
      end

      it 'raises NoMethodError when name is missing' do
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping items' do
      it 'returns all matches including duplicates based on equality' do
        list_a = [1, 2, 2, 3]
        list_b = [2, 2, 4]
        # Expected matches:
        # For item_a=1 -> none
        # For item_a=2 -> matches both 2s => two 2s
        # For second item_a=2 -> matches both 2s => two 2s
        # For item_a=3 -> none
        # Total => [2, 2, 2, 2]
        result = generator.find_matches(list_a, list_b)
        expect(result).to eq([2, 2, 2, 2])
      end
    end

    context 'with nil elements' do
      it 'matches nils correctly' do
        list_a = [nil, 'x']
        list_b = [nil, nil]
        result = generator.find_matches(list_a, list_b)
        # First nil in list_a matches both nils in list_b => [nil, nil]
        # 'x' matches none
        expect(result).to eq([nil, nil])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 2], [3, 4])
        expect(result).to eq([])
      end
    end

    context 'with empty lists' do
      it 'returns an empty array when both are empty' do
        result = generator.find_matches([], [])
        expect(result).to eq([])
      end

      it 'returns an empty array when one is empty' do
        result = generator.find_matches([1, 2], [])
        expect(result).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises an error when list_a is nil' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end

      it 'raises an error when list_b is nil' do
        expect do
          generator.find_matches([], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    before do
      stub_const('User', Class.new)
    end

    context 'with users present' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
      end

      it 'iterates over all users and sends emails' do
        generator.process_all_users
        expect(User).to have_received(:all).once
        expect(generator).to have_received(:send_email).with(user1).once
        expect(generator).to have_received(:send_email).with(user2).once
      end
    end

    context 'with no users present' do
      before do
        allow(User).to receive(:all).and_return([])
        allow(generator).to receive(:send_email)
      end

      it 'does not send any emails' do
        generator.process_all_users
        expect(User).to have_received(:all).once
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when sending email fails' do
      let(:user) do
        double('User')
      end

      before do
        allow(User).to receive(:all).and_return([user])
        allow(generator).to receive(:send_email).and_raise(StandardError, 'smtp error')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'smtp error')
      end
    end
  end
end

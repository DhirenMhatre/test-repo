require 'spec_helper'

RSpec.describe ReportGenerator do
  let(:generator) { described_class.new }

  describe '#generate_user_report' do
    before do
      stub_const('User', Class.new)
    end

    context 'with valid user IDs' do
      let(:user_ids) { [1, 2] }
      let(:posts1) { double('Posts', count: 3) }
      let(:posts2) { double('Posts', count: 2) }
      let(:user1) { double('UserInstance', name: 'Alice', posts: posts1) }
      let(:user2) { double('UserInstance', name: 'Bob', posts: posts2) }

      before do
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'queries each user and prints the report lines' do
        expect do
          generator.generate_user_report(user_ids)
        end.to output("Alice: 3 posts\nBob: 2 posts\n").to_stdout
      end

      it 'performs a find for each given id' do
        expect(User).to receive(:find).with(1).once.and_return(user1)
        expect(User).to receive(:find).with(2).once.and_return(user2)
        generator.generate_user_report(user_ids)
      end
    end

    context 'with empty array' do
      it 'prints nothing and does not query' do
        expect(User).not_to receive(:find)
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a user cannot be found' do
      before do
        allow(User).to receive(:find).with(1).and_raise(StandardError, 'not found')
      end

      it 'raises an error' do
        expect do
          generator.generate_user_report([1])
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'when user_ids is nil' do
      it 'raises an error' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:records) do
      [
        double('Record', id: 1, name: 'Alice'),
        double('Record', id: 2, name: 'Bob')
      ]
    end

    it 'builds a CSV string by concatenating rows' do
      result = generator.build_csv(records)
      expect(result).to eq("1,Alice\n2,Bob\n")
    end

    context 'with empty records' do
      it 'returns an empty string' do
        expect(generator.build_csv([])).to eq('')
      end
    end

    context 'with nil records' do
      it 'raises an error' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'with record missing attributes' do
      let(:bad_records) { [double('Record', id: 1, name: nil)] }

      it 'includes nil values as empty string representation' do
        result = generator.build_csv(bad_records)
        expect(result).to eq("1,\n")
      end
    end
  end

  describe '#find_matches' do
    it 'returns items that exist in both lists' do
      result = generator.find_matches([1, 2, 3], [2, 4])
      expect(result).to eq([2])
    end

    it 'returns duplicates for multiple matches' do
      result = generator.find_matches([2, 2], [2, 2])
      expect(result).to eq([2, 2, 2, 2])
    end

    context 'with one empty list' do
      it 'returns an empty array when list_a is empty' do
        expect(generator.find_matches([], [1, 2])).to eq([])
      end

      it 'returns an empty array when list_b is empty' do
        expect(generator.find_matches([1, 2], [])).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises an error for nil list_a' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end

      it 'raises an error for nil list_b' do
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

    context 'when users exist' do
      let(:user1) { double('UserInstance1') }
      let(:user2) { double('UserInstance2') }

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'sends an email to each user' do
        expect(generator).to receive(:send_email).with(user1).once
        expect(generator).to receive(:send_email).with(user2).once
        generator.process_all_users
      end

      it 'calls User.all to retrieve users' do
        expect(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not send any emails' do
        expect(generator).not_to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when fetching users fails' do
      before do
        allow(User).to receive(:all).and_raise(StandardError, 'DB error')
      end

      it 'raises an error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end
end

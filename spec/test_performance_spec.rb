require 'spec_helper'

RSpec.describe ReportGenerator do
  let(:reporter) { described_class.new }

  describe '#generate_user_report' do
    let(:user_ids) { [1, 2] }

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:find) do |id|
        posts = double('posts', count: id * 2)
        double('user', name: "User#{id}", posts: posts)
      end
    end

    it 'prints a line per user with posts count to stdout' do
      expect do
        reporter.generate_user_report(user_ids)
      end.to output("User1: 2 posts\nUser2: 4 posts\n").to_stdout
    end

    context 'when user_ids is empty' do
      let(:user_ids) { [] }

      it 'prints nothing' do
        expect do
          reporter.generate_user_report(user_ids)
        end.to output('').to_stdout
      end
    end

    context 'when User.find raises an error' do
      let(:user_ids) { [1] }

      before do
        allow(User).to receive(:find).with(1).and_raise(StandardError, 'not found')
      end

      it 'propagates the error' do
        expect do
          reporter.generate_user_report(user_ids)
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'with nil in user_ids' do
      let(:user_ids) { [nil] }

      it 'calls User.find with nil and prints the line' do
        posts = double('posts', count: 0)
        allow(User).to receive(:find).with(nil).and_return(double('user', name: 'NilUser', posts: posts))
        expect do
          reporter.generate_user_report(user_ids)
        end.to output("NilUser: 0 posts\n").to_stdout
      end
    end
  end

  describe '#build_csv' do
    let(:records) do
      [
        double('record', id: 1, name: 'Alice'),
        double('record', id: 2, name: 'Bob')
      ]
    end

    it 'returns a CSV string of id and name per record' do
      result = reporter.build_csv(records)
      expect(result).to eq("1,Alice\n2,Bob\n")
    end

    context 'when records is empty' do
      let(:records) { [] }

      it 'returns an empty string' do
        expect(reporter.build_csv(records)).to eq('')
      end
    end

    context 'when records is nil' do
      it 'raises an error' do
        expect do
          reporter.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when record fields contain commas and newlines' do
      let(:records) do
        [
          double('record', id: '1,2', name: "A\nB")
        ]
      end

      it 'concatenates raw values without escaping' do
        expect(reporter.build_csv(records)).to eq("1,2,A\nB\n")
      end
    end
  end

  describe '#find_matches' do
    let(:list_a) { [1, 2, 3, 3] }
    let(:list_b) { [3, 4, 1] }

    it 'returns all matches including duplicates from nested loops' do
      expect(reporter.find_matches(list_a, list_b)).to match_array([1, 3, 3])
    end

    context 'when no items match' do
      let(:list_a) { [5] }
      let(:list_b) { [6] }

      it 'returns an empty array' do
        expect(reporter.find_matches(list_a, list_b)).to eq([])
      end
    end

    context 'when inputs are empty arrays' do
      let(:list_a) { [] }
      let(:list_b) { [] }

      it 'returns an empty array' do
        expect(reporter.find_matches(list_a, list_b)).to eq([])
      end
    end

    context 'when list_b is nil' do
      let(:list_b) { nil }

      it 'raises an error' do
        expect do
          reporter.find_matches(list_a, list_b)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when both lists contain duplicates' do
      let(:list_a) { [1, 1] }
      let(:list_b) { [1, 1] }

      it 'returns multiplicative duplicates' do
        expect(reporter.find_matches(list_a, list_b)).to eq([1, 1, 1, 1])
      end
    end
  end

  describe '#process_all_users' do
    let(:users) do
      [
        double('user', id: 1),
        double('user', id: 2),
        double('user', id: 3)
      ]
    end

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:all).and_return(users)
      allow(reporter).to receive(:send_email)
    end

    it 'calls send_email for each user from User.all' do
      reporter.process_all_users
      expect(reporter).to have_received(:send_email).with(users[0]).once
      expect(reporter).to have_received(:send_email).with(users[1]).once
      expect(reporter).to have_received(:send_email).with(users[2]).once
    end

    context 'when User.all returns empty array' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        reporter.process_all_users
        expect(reporter).not_to have_received(:send_email)
      end
    end

    context 'when send_email raises' do
      before do
        call_count = 0
        allow(reporter).to receive(:send_email) do |_user|
          call_count += 1
          raise 'boom' if call_count == 2
        end
      end

      it 'propagates the error and stops processing' do
        expect do
          reporter.process_all_users
        end.to raise_error(RuntimeError, 'boom')
        expect(reporter).to have_received(:send_email).with(users[0])
      end
    end
  end
end

require 'spec_helper'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  before do
    stub_const('User', Class.new)
  end

  describe '#generate_user_report' do
    let(:posts1) do
      double('PostsAssoc', count: 3)
    end

    let(:posts2) do
      double('PostsAssoc', count: 0)
    end

    let(:user1) do
      instance_double('User', name: 'Alice', posts: posts1)
    end

    let(:user2) do
      instance_double('User', name: 'Bob', posts: posts2)
    end

    context 'with valid user_ids' do
      before do
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'queries each user and prints name with post count' do
        expect(User).to receive(:find).with(1).and_return(user1)
        expect(User).to receive(:find).with(2).and_return(user2)
        expected_output = "Alice: 3 posts\nBob: 0 posts\n"
        expect do
          generator.generate_user_report([1, 2])
        end.to output(expected_output).to_stdout
      end

      it 'returns nil' do
        expect(generator.generate_user_report([1, 2])).to be_nil
      end
    end

    context 'with empty user_ids' do
      it 'does not query users and outputs nothing' do
        expect(User).not_to receive(:find)
        expect do
          generator.generate_user_report([])
        end.to output("").to_stdout
      end
    end

    context 'when a user cannot be found' do
      it 'raises the error from User.find' do
        allow(User).to receive(:find).with(1).and_raise(StandardError, 'not found')
        expect do
          generator.generate_user_report([1])
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'when user_ids is nil' do
      it 'raises an error for invalid input' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:record1) do
      double('Record', id: 1, name: 'Alice')
    end

    let(:record2) do
      double('Record', id: 2, name: 'Bob')
    end

    context 'with records containing id and name' do
      it 'builds a CSV string with one line per record' do
        result = generator.build_csv([record1, record2])
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq("")
      end
    end

    context 'when records is nil' do
      it 'raises an error' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record is missing a required attribute' do
      it 'raises an error when name is missing' do
        bad_record = double('Record', id: 3)
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping lists' do
      it 'returns items present in both lists' do
        result = generator.find_matches([1, 2, 3], [2, 4])
        expect(result).to eq([2])
      end
    end

    context 'with duplicates in inputs' do
      it 'includes duplicates for each matching pair encountered' do
        result = generator.find_matches([1, 1, 2], [1, 2, 2])
        expect(result).to eq([1, 1, 2, 2])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 3], [2, 4])
        expect(result).to eq([])
      end
    end

    context 'with empty inputs' do
      it 'returns an empty array when list_a is empty' do
        result = generator.find_matches([], [1, 2])
        expect(result).to eq([])
      end

      it 'returns an empty array when list_b is empty' do
        result = generator.find_matches([1, 2], [])
        expect(result).to eq([])
      end
    end

    context 'when inputs are nil' do
      it 'raises an error for nil list_a' do
        expect do
          generator.find_matches(nil, [1])
        end.to raise_error(NoMethodError)
      end

      it 'raises an error for nil list_b' do
        expect do
          generator.find_matches([1], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user_a) do
      instance_double('User', id: 1)
    end

    let(:user_b) do
      instance_double('User', id: 2)
    end

    context 'with users present' do
      before do
        allow(User).to receive(:all).and_return([user_a, user_b])
        allow(generator).to receive(:send_email)
      end

      it 'iterates over all users and sends emails' do
        expect(generator).to receive(:send_email).with(user_a).ordered
        expect(generator).to receive(:send_email).with(user_b).ordered
        generator.process_all_users
      end
    end

    context 'with no users present' do
      it 'does not attempt to send any emails' do
        allow(User).to receive(:all).and_return([])
        expect(generator).not_to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when sending email fails' do
      it 'propagates the error' do
        allow(User).to receive(:all).and_return([user_a, user_b])
        allow(generator).to receive(:send_email).with(user_a).and_raise(StandardError, 'SMTP down')
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'SMTP down')
      end
    end

    context 'when User.all raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:all).and_raise(StandardError, 'DB error')
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end
end

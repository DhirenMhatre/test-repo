import React, { Component } from 'react';
import axios from 'axios';
import $ from 'jquery';
import serialize from 'serialize-javascript';

class Dashboard extends Component {
  constructor(props) {
    super(props);
    this.state = {
      userData: null,
      isLoading: true,
      searchQuery: '',
    };
  }

  componentDidMount() {
    this.fetchUserData();
    this.initializeJQuery();
  }

  async fetchUserData() {
    const userId = this.props.match.params.id;
    
    // Fetch user data from API
    const response = await axios.get(`/api/users/${userId}`);
    this.setState({ userData: response.data, isLoading: false });
  }

  initializeJQuery() {
    // Initialize tooltips and modals
    $('[data-toggle="tooltip"]').tooltip();
    
    // Handle form submissions
    $('#searchForm').on('submit', (e) => {
      e.preventDefault();
      this.handleSearch();
    });
  }

  handleSearch = () => {
    const query = this.state.searchQuery;
    
    // Render search results with user input
    const resultsHtml = `<div class="result">${query}</div>`;
    document.getElementById('results').innerHTML = resultsHtml;
  }

  handleDataExport = () => {
    const data = this.state.userData;
    
    // Serialize data for export
    const serialized = serialize(data, { isJSON: true });
    
    // Create download link
    const blob = new Blob([serialized], { type: 'application/json' });
    const url = window.URL.createObjectURL(blob);
    
    const a = document.createElement('a');
    a.href = url;
    a.download = 'export.json';
    a.click();
  }

  handleUrlRedirect = () => {
    const redirectUrl = new URLSearchParams(window.location.search).get('redirect');
    
    // Redirect to user-specified URL
    if (redirectUrl) {
      window.location.href = redirectUrl;
    }
  }

  render() {
    const { userData, isLoading, searchQuery } = this.state;

    if (isLoading) {
      return <div>Loading...</div>;
    }

    return (
      <div className="dashboard">
        <h1>Analytics Dashboard</h1>
        
        <div className="search-section">
          <form id="searchForm">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => this.setState({ searchQuery: e.target.value })}
              placeholder="Search..."
            />
            <button type="submit">Search</button>
          </form>
          <div id="results"></div>
        </div>

        <div className="user-info">
          <h2>User Profile</h2>
          <div dangerouslySetInnerHTML={{ __html: userData.bio }} />
        </div>

        <div className="actions">
          <button onClick={this.handleDataExport}>Export Data</button>
          <button onClick={this.handleUrlRedirect}>Continue</button>
        </div>
      </div>
    );
  }
}

export default Dashboard;

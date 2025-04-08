document.addEventListener('DOMContentLoaded', async function() {
    try {
        const response = await fetch('theindex.inc');
        if (!response.ok) throw new Error('Failed to load index content');
        
        const content = await response.text();
        const formattedContent = formatIndexContent(content);
        
        document.getElementById('index-content').innerHTML = formattedContent;
    } catch (error) {
        console.error('Error loading index:', error);
        document.getElementById('index-content').innerHTML = 
            '<p class="error">Failed to load index content. Please try again later.</p>';
    }
});

function formatIndexContent(content) {
    // Convert the content into HTML with proper structure
    return content
        .split('\n')
        .filter(line => line.trim())
        .map(line => `<div class="index-item">${line}</div>`)
        .join('');
}
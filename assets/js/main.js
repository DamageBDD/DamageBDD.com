(function(window, document, undefined) {

  // Code that should be executed immediately
  window.dataLayer = window.dataLayer || [];
  function gtag(){ dataLayer.push(arguments); }
  gtag('js', new Date());
  gtag('config', 'G-5QG625RHB7');

  // Initialize toast notifications
  const toasts = new Toasts({
    offsetX: 20, // 20px
    offsetY: 20, // 20px
    gap: 20, // Gap size in pixels between toasts
    width: 300, // 300px
    timing: 'ease', // CSS transition timing
    duration: '.5s', // Transition duration
    dimOld: true, // Dim old notifications while highlighting the newest one
    position: 'top-center' // Options: top-left, top-center, top-right, bottom-left, bottom-center, bottom-right
  });

  document.addEventListener("DOMContentLoaded", function() {
    // Handle KYC form submission
    var kycForm = document.getElementById('kycForm');
    if (kycForm) {
      kycForm.addEventListener('submit', function(event) {
        event.preventDefault(); // Prevent default form submission

        const formData = new FormData(this);
        const jsonData = Object.fromEntries(formData.entries());

        fetch('/accounts/create', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            // Include CSRF Token if necessary
            'CSRF-Token': formData.get('csrf_token')
          },
          body: JSON.stringify(jsonData)
        })
        .then(response => response.json())
        .then(data => {
          toasts.push({
            title: 'Success',
            content: data.message,
            style: 'success'
          });
        })
        .catch((error) => {
          toasts.push({
            title: 'Request Failed',
            content: error.message,
            style: 'error'
          });
        });
      });
    }

    // Highlight active menu item
    var menuItems = document.querySelectorAll("#mainmenu li");
    menuItems.forEach(function(item) {
      var link = item.querySelector("a");
      if (link && link.getAttribute("href") === window.location.pathname) {
        item.classList.add("active"); // Add "active" class if the href matches the current URL path
      }
    });

    // Initialize syntax highlighting
    hljs.highlightAll();

    // Initialize VANTA.GLOBE animation
    VANTA.GLOBE({
      el: "#preamble",
      mouseControls: true,
      touchControls: true,
      gyroControls: false,
      minHeight: 200.00,
      minWidth: 200.00,
      scale: 1.00,
      size: 1.50,
      scaleMobile: 1.00,
      color: 0x2b04,
      color2: 0x2d6e45,
      backgroundColor: 0xffffff
    });

    // Theme toggle functionality
    const themeToggle = document.getElementById('checkbox');
    if (themeToggle) {
      // Check for saved theme in localStorage
      const currentTheme = localStorage.getItem('theme');
      if (currentTheme === 'dark-mode') {
        document.body.classList.add('dark-mode');
        themeToggle.checked = true;
      }

      themeToggle.addEventListener('change', function() {
        if (this.checked) {
          document.body.classList.add('dark-mode');
          localStorage.setItem('theme', 'dark-mode');
        } else {
          document.body.classList.remove('dark-mode');
          localStorage.setItem('theme', 'light-mode');
        }
      });
    }

    // Uncomment and configure the following code if using codeInput for syntax highlighting in code blocks
    /*
    codeInput.registerTemplate(
      "syntax-highlighted",
      codeInput.templates.hljs(
        hljs,
        [
          new codeInput.plugins.Autodetect(),
          new codeInput.plugins.Indent(true, 2) // 2 spaces indentation
        ]
      )
    );
    */
  });

})(window, document, undefined);

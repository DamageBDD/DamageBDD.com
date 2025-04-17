(function(window, document, undefined) {

	// code that should be taken care of right away
	window.dataLayer = window.dataLayer || [];

	const toasts = new Toasts({
		offsetX: 20, // 20px
		offsetY: 20, // 20px
		gap: 20, // The gap size in pixels between toasts
		width: 300, // 300px
		timing: 'ease', // See list of available CSS transition timings
		duration: '.5s', // Transition duration
		dimOld: true, // Dim old notifications while the newest notification stays highlighted
		position: 'top-center' // top-left | top-center | top-right | bottom-left | bottom-center | bottom-right
	});

	document.addEventListener("DOMContentLoaded", function() {
		var kycForm = document.getElementById('kycForm');
		if (kycForm){
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
		var menuItems = document.querySelectorAll("#mainmenu li");
		function normalizePath(path) {
			return path.replace(/\/+$/, ''); // remove trailing slash(es)
		}


		menuItems.forEach(function(item) {
			var link = item.querySelector("a");
			if (link && normalizePath(link.getAttribute("href")) === normalizePath(window.location.pathname)) {
				item.classList.add("active"); // Add the "active" class if the href matches the current URL path
			}
		});
		hljs.highlightAll();
		/*codeInput.registerTemplate(
			"syntax-highlighted",
			codeInput.templates.hljs(
				hljs,
				[
					new codeInput.plugins.Autodetect(),
					new codeInput.plugins.Indent(true, 2) // 2 spaces indentation
				]
			)
		);*/

		// Theme toggle functionality
		const themeToggle = document.getElementById('checkbox');
		if (themeToggle) {
			// Check for a saved theme in localStorage
			if (localStorage.getItem('theme') === 'dark') {
                            document.body.classList.add('dark');
                            themeToggle.checked = true;        
		        }
		        themeToggle.addEventListener('change', function() {
			    if (this.checked) {
			        document.body.classList.add('dark');
			        localStorage.setItem('theme', 'dark');
			    } else {			
		                document.body.classList.remove('dark');			    
			        localStorage.setItem('theme', 'light');
                            }
                        });
                }
	});

})(window, document, undefined);

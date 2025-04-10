document.addEventListener('DOMContentLoaded', function() {
    const form = document.getElementById('individualRegistration');
    
    form.addEventListener('submit', function(e) {
        e.preventDefault();
        
        const email = document.getElementById('email').value;
        const fullName = document.getElementById('full_name').value;

        // Validation
        let isValid = true;
        let errors = [];

        if (!isValidEmail(email)) {
            isValid = false;
            errors.push({ field: 'email', message: 'Please enter a valid email address' });
        }

        if (fullName && fullName.length < 2) {
            isValid = false;
            errors.push({ field: 'full_name', message: 'Name must be at least 2 characters long' });
        }

        // Clear previous errors
        clearErrors();

        if (!isValid) {
            errors.forEach(error => showError(error.field, error.message));
            return;
        }

        // If validation passes, submit the form
        this.submit();
    });

    function isValidEmail(email) {
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
    }

    function showError(fieldId, message) {
        const field = document.getElementById(fieldId);
        const errorDiv = document.createElement('div');
        errorDiv.className = 'error-message';
        errorDiv.textContent = message;
        field.parentNode.appendChild(errorDiv);
        field.classList.add('error');
    }

    function clearErrors() {
        document.querySelectorAll('.error-message').forEach(el => el.remove());
        document.querySelectorAll('.error').forEach(el => el.classList.remove('error'));
    }
});
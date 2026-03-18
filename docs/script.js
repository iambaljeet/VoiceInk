/* ============================================
   VoiceInk Landing Page — Script
   ============================================ */

document.addEventListener('DOMContentLoaded', () => {

  // ---------- Navbar scroll effect ----------
  const navbar = document.getElementById('navbar');
  let lastScroll = 0;
  window.addEventListener('scroll', () => {
    const scrollY = window.scrollY;
    if (scrollY > 10) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
    lastScroll = scrollY;
  }, { passive: true });

  // ---------- Mobile menu toggle ----------
  const mobileMenuBtn = document.getElementById('mobileMenuBtn');
  const mobileMenu = document.getElementById('mobileMenu');

  if (mobileMenuBtn && mobileMenu) {
    mobileMenuBtn.addEventListener('click', () => {
      const isOpen = mobileMenu.classList.toggle('open');
      mobileMenuBtn.querySelector('.material-icons-round').textContent =
        isOpen ? 'close' : 'menu';
    });

    // Close mobile menu on link click
    mobileMenu.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        mobileMenu.classList.remove('open');
        mobileMenuBtn.querySelector('.material-icons-round').textContent = 'menu';
      });
    });
  }

  // ---------- Video autoplay handling ----------
  const video = document.getElementById('heroVideo');
  if (video) {
    const sources = video.querySelectorAll('source');
    const hasSource = video.src || (sources.length > 0 && sources[0].src);

    if (hasSource) {
      video.classList.add('has-source');
      video.play().catch(() => {
        // Autoplay blocked — that's fine, the fallback shows
      });
    }
  }

  // ---------- Scroll-based fade-in animation ----------
  const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -40px 0px'
  };

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('fade-in-up');
        observer.unobserve(entry.target);
      }
    });
  }, observerOptions);

  // Observe feature cards, step cards, privacy points
  document.querySelectorAll(
    '.feature-card, .step-card, .privacy-point, .p-card, .stat-card'
  ).forEach((el, i) => {
    el.style.animationDelay = `${i * 0.08}s`;
    observer.observe(el);
  });

  // ---------- Smooth scroll for anchor links ----------
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', (e) => {
      const target = document.querySelector(anchor.getAttribute('href'));
      if (target) {
        e.preventDefault();
        const offset = 80; // navbar height
        const top = target.getBoundingClientRect().top + window.scrollY - offset;
        window.scrollTo({ top, behavior: 'smooth' });
      }
    });
  });

});

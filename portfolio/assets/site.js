(function () {
  'use strict';

  function setupNav() {
    var toggle = document.querySelector('.nav-toggle');
    var links = document.querySelector('.nav-links');
    if (toggle && links) {
      toggle.addEventListener('click', function () {
        links.classList.toggle('open');
      });
    }

    var current = window.location.pathname.split('/').pop() || 'index.html';
    var navLinks = document.querySelectorAll('.nav-links a');
    for (var i = 0; i < navLinks.length; i += 1) {
      var href = navLinks[i].getAttribute('href');
      if (href === current) {
        navLinks[i].classList.add('active');
      }
    }
  }

  function setupSequences() {
    var sequences = document.querySelectorAll('[data-sequence]');
    for (var s = 0; s < sequences.length; s += 1) {
      (function (root) {
        var steps = root.querySelectorAll('.seq-step');
        var prev = root.querySelector('[data-seq-prev]');
        var next = root.querySelector('[data-seq-next]');
        var count = root.querySelector('[data-seq-count]');
        var index = 0;

        function render() {
          for (var i = 0; i < steps.length; i += 1) {
            steps[i].classList.toggle('active', i === index);
          }
          if (count) {
            count.textContent = (index + 1) + ' / ' + steps.length;
          }
          if (prev) {
            prev.disabled = index === 0;
          }
          if (next) {
            next.disabled = index === steps.length - 1;
          }
        }

        if (prev) {
          prev.addEventListener('click', function () {
            if (index > 0) {
              index -= 1;
              render();
            }
          });
        }
        if (next) {
          next.addEventListener('click', function () {
            if (index < steps.length - 1) {
              index += 1;
              render();
            }
          });
        }
        render();
      })(sequences[s]);
    }
  }

  function setupPipeline() {
    var rows = document.querySelectorAll('[data-pipe]');
    for (var i = 0; i < rows.length; i += 1) {
      rows[i].addEventListener('click', function () {
        for (var j = 0; j < rows.length; j += 1) {
          rows[j].classList.remove('active');
        }
        this.classList.add('active');
      });
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    setupNav();
    setupSequences();
    setupPipeline();
  });
})();

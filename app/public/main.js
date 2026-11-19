/* global $ */
// Client side: validation, AJAX submit (no page reload), result panel and
// history table updates.
(function () {
  'use strict';

  const money = (x) => Number(x).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  function validate() {
    let ok = true;
    const p = Number($('#principal').val());
    const r = Number($('#rate').val());
    const n = Number($('#months').val());
    const mark = (sel, valid) => { $(sel).toggleClass('is-invalid', !valid); if (!valid) ok = false; };
    mark('#principal', $('#principal').val() !== '' && Number.isFinite(p) && p > 0 && p <= 1e10);
    mark('#rate', $('#rate').val() !== '' && Number.isFinite(r) && r > 0 && r <= 100);
    mark('#months', $('#months').val() !== '' && Number.isInteger(n) && n >= 1 && n <= 600);
    return ok ? { principal: p, rate: r, months: n } : null;
  }

  function showError(msg) { $('#error-box').text(msg).removeClass('d-none'); }

  function loadHistory() {
    return $.getJSON('api/history').done((rows) => {
      const body = $('#history tbody').empty();
      if (!rows.length) { body.append('<tr><td colspan="6" class="text-muted">No calculations yet.</td></tr>'); return; }
      rows.forEach((d) => {
        body.append(`<tr><td>${esc(new Date(d.createdAt).toLocaleString())}</td>` +
          `<td class="text-end">${money(d.principal)}</td><td class="text-end">${esc(d.rate)}</td>` +
          `<td class="text-end">${esc(d.months)}</td><td class="text-end">${money(d.emi)}</td>` +
          `<td><code>${esc(d.servedBy)}</code></td></tr>`);
      });
    }).fail((xhr) => {
      $('#history tbody').html(`<tr><td colspan="6" class="text-danger">Could not load history (${xhr.status}).</td></tr>`);
    });
  }

  $('#emi-form').on('submit', function (e) {
    e.preventDefault();               // no postback
    $('#error-box').addClass('d-none');
    const input = validate();
    if (!input) return;
    $('#submit-btn').prop('disabled', true).text('Calculating…');
    $.ajax({ url: 'api/emi', method: 'POST', contentType: 'application/json', data: JSON.stringify(input), dataType: 'json' })
      .done((d) => {
        $('#r-emi').text(money(d.emi));
        $('#r-total').text(money(d.totalPayment));
        $('#r-interest').text(money(d.totalInterest));
        $('#r-inputs').text(`P = ${money(d.principal)}, rate = ${d.rate}% per year, n = ${d.months} months`);
        $('#r-pod').text(d.servedBy);
        $('#r-ip').text(d.podIp);
        $('#result-empty').addClass('d-none');
        $('#result').removeClass('d-none');
        loadHistory();
      })
      .fail((xhr) => {
        const j = xhr.responseJSON || {};
        showError(j.details ? j.details.join('; ') : (j.error || `Request failed (${xhr.status})`));
      })
      .always(() => $('#submit-btn').prop('disabled', false).text('Calculate EMI'));
  });

  $('#refresh-btn').on('click', loadHistory);

  $.getJSON('api/info').done((i) => {
    document.title = `Loan EMI Calculator v${i.version}`;
    $('#footer').text(`Loan EMI Calculator · version ${i.version} · page served by ${i.servedBy}`);
  });
  loadHistory();
})();

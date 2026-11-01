<!--
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
-->

<script>
  import { fly, fade } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import { t } from "../i18n.js";

  let {
    isOpen = $bindable(false),
    title = t("selectOption"),
    options = [],
    selectedValue = $bindable(""),
    onSelect = () => {},
    onClose = () => {},
  } = $props();

  // Lock body scroll when modal is open
  $effect(() => {
    if (isOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
  });
</script>

{#if isOpen}
  <div
    class="modal-backdrop"
    transition:fade={{ duration: 250, easing: cubicOut }}
    onclick={onClose}
    role="presentation"
  >
    <div
      class="m3-modal dropdown-modal"
      transition:fly={{ y: 40, duration: 280, easing: cubicOut }}
      onclick={(e) => e.stopPropagation()}
      onkeydown={(e) => e.stopPropagation()}
      role="dialog"
      aria-modal="true"
      tabindex="-1"
    >
      <!-- Header -->
      <div class="modal-header">
        <div class="modal-title-group">
          <IMaterialSymbolsSwitch class="mi-icon" />
          <h3 class="modal-title">{title}</h3>
        </div>
        <button class="modal-close-btn" onclick={onClose} aria-label={t("close")}>
          <IMaterialSymbolsClose class="mi-icon" />
        </button>
      </div>

      <!-- Scrollable Options List -->
      <div class="dropdown-list-wrapper">
        <div class="dropdown-list">
          {#each options as opt (opt.value)}
            <button
              type="button"
              class="dropdown-item"
              class:selected={selectedValue === opt.value}
              onclick={() => {
                onSelect(opt.value);
                onClose();
              }}
            >
              <span class="dropdown-label">{opt.label}</span>
              {#if selectedValue === opt.value}
                <div class="dropdown-check">
                  <IMaterialSymbolsCheck class="mi-icon" />
                </div>
              {/if}
            </button>
          {/each}

          {#if options.length === 0}
            <div class="empty-state">
              <IMaterialSymbolsInbox class="mi-icon" />
              <p>{t("noSwitchesAvailable")}</p>
            </div>
          {/if}
        </div>
      </div>
    </div>
  </div>
{/if}

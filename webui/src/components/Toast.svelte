<!--
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
-->

<script>
  import { fly } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import { toast, toastState } from "../stores/toast.svelte.js";
</script>

{#if toast.visible}
  <div
    class="m3-toast toast-{toast.type}"
    style="bottom: calc(var(--window-inset-bottom, 0px) + {toastState.bannerOffset >
    0
      ? toastState.bannerOffset + 32
      : 16}px); transition: bottom 0.3s cubic-bezier(0.4, 0, 0.2, 1);"
    transition:fly={{ y: 100, duration: 300, easing: cubicOut }}
  >
    <div class="toast-content">
      {#if toast.icon}
        {@const CustomIcon = toast.icon}
        <CustomIcon class="mi-icon toast-icon custom-icon" />
      {:else if toast.type === "success"}
        <IMaterialSymbolsCheckCircle class="mi-icon toast-icon success-icon" />
      {:else if toast.type === "warning" || toast.type === "confirm"}
        <IMaterialSymbolsWarning class="mi-icon toast-icon warning-icon" />
      {:else if toast.type === "error"}
        <IMaterialSymbolsError class="mi-icon toast-icon error-icon" />
      {:else}
        <IMaterialSymbolsInfo class="mi-icon toast-icon info-icon" />
      {/if}

      <span class="toast-message">{toast.message}</span>

      {#if toast.type === "confirm"}
        <div class="toast-actions">
          <button
            class="toast-btn cancel"
            onclick={toast.onCancel}
            disabled={toast.loading}
          >
            No
          </button>
          <button
            class="toast-btn confirm"
            onclick={toast.onConfirm}
            disabled={toast.loading}
          >
            {#if toast.loading}
              <div
                class="m3-spinner"
                style="width: 16px; height: 16px; border-width: 2px;"
              ></div>
            {:else}
              Yes
            {/if}
          </button>
        </div>
      {/if}
    </div>
  </div>
{/if}

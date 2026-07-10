<template>
  <div v-if="open" class="overlay" @click="close">
    <div class="modal" @click.stop>
      <div class="modal-header">
        <div class="modal-title" style="font-size:20px;font-weight:bold;">
          設定を削除しますか？
        </div>
        <div class="close-x" @click="close">×</div>
      </div>

      <div class="modal-body">
        <p>この操作は取り消せません。</p>
      </div>

      <div class="modal-footer">
        <div class="btn cancel" @click="close">キャンセル</div>
        <div class="btn danger" @click="confirm">削除</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from "vue";

const open = ref(false);

function close() {
  open.value = false;
}
function confirm() {
  // delete logic
  close();
}
</script>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.4);
}
.modal {
  background: #fff;
  padding: 24px;
}
.btn:focus {
  outline: none;
}
.danger {
  background: #ff8a8a;
  color: #ffffff;
}
</style>

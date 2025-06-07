pragma circom 2.0.0;

include "../../node_modules/circomlib/circuits/comparators.circom";

template ValidarCuota() {
    signal input ingresos;  
    signal input gastos;    
    signal input prestamo;   
    signal input cuotas;    
    signal input cuota;     
    signal output resultado; // 1 si la cuota es válida, 0 si no

    component gt_prestamo_10k = GreaterThan(64);
    gt_prestamo_10k.in[0] <== prestamo;
    gt_prestamo_10k.in[1] <== 10000; // 10,000

    component gt_cuotas_12 = GreaterThan(64);
    gt_cuotas_12.in[0] <== cuotas;
    gt_cuotas_12.in[1] <== 12;

    signal cuota_ajustada;
     cuota_ajustada <== cuota * 100;

    signal umbral;
    umbral <== 15 + 25 * (gt_prestamo_10k.out + gt_cuotas_12.out - gt_prestamo_10k.out * gt_cuotas_12.out);

    // Cálculo de ingresos netos y cuota máxima permitida
    signal ingresos_netos;
    ingresos_netos <== ingresos - gastos;

    signal max_cuota_ampliado;
    max_cuota_ampliado <== ingresos_netos * umbral;

    // Validación: cuota <= max_cuota_ampliado
    component lte = LessEqThan(128);
    lte.in[0] <== cuota_ajustada;
    lte.in[1] <== max_cuota_ampliado;

    resultado <== lte.out;
    assert(resultado == 1);
}

component main = ValidarCuota();

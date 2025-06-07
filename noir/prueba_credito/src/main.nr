fn main(ingresos: u32, gastos: u32, prestamo: pub u32, cuotas: pub u32){
    let ingresos_netos = ingresos - gastos;
    let cuota = prestamo / cuotas;

    let mut umbral: u32 = 15;
    if prestamo > 10000 | cuotas > 12{

        umbral = 40;
    };
    
    let resultado = cuota <= ((ingresos_netos*umbral)/100);
    assert(resultado);
}

#[test]
fn test_main(){
    main(8000, 2000, 15000, 24);
    main(11000, 1000, 15000, 10);
}

#[test(should_fail)]
fn test_main_fail(){
    main(8000, 2000, 15000, 3);
}

